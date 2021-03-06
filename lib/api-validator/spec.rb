module ApiValidator
  class Spec

    require 'api-validator/spec/results'

    module SharedClassAndInstanceMethods
      def shared_examples
        @shared_examples ||= begin
          if self.respond_to?(:superclass) && self.superclass.respond_to?(:shared_examples)
            self.superclass.shared_examples || Hash.new
          else
            Hash.new
          end
        end
      end

      def shared_example(name, &block)
        self.shared_examples[name] = block
      end

      def validations
        @validations ||= []
      end

      def sort_validations!
        @validations = validations.sort do |a, b|
          if a.dependencies.include?(b.dependency_name)
            1
          elsif b.dependencies.include?(a.dependency_name)
            -1
          else
            validations.index(a) <=> validations.index(b)
          end
        end
      end

      def describe(name, options = {}, &block)
        validation = self.new(name, options.merge(:parent => self), &block)
        self.validations << validation
        validation
      end
      alias context describe

      def cache
        @cache ||= Hash.new
      end

      def get(path, context=self)
        if Symbol === path
          path = "/#{path}"
        end

        pointer = JsonPointer.new(cache, path, :symbolize_keys => true)
        unless pointer.exists?
          return parent ? parent.get(path, context) : nil
        end
        val = pointer.value
        Proc === val ? context.instance_eval(&val) : val
      end

      def set(path, val=nil, &block)
        if Symbol === path
          path = "/#{path}"
        end

        pointer = JsonPointer.new(cache, path, :symbolize_keys => true)
        pointer.value = block_given? ? block : val
        val
      end

      def setup_blocks
        @setup_blocks ||= []
      end

      def setup(&block)
        setup_blocks << block
      end
    end

    class << self
      include SharedClassAndInstanceMethods
    end
    include SharedClassAndInstanceMethods

    def self.parent; end

    def self.run
      setup_blocks.each do |block|
        block.call
      end

      sort_validations!
      validations.inject(Results.new(self.new(''), [])) do |memo, validation|
        results = validation.run
        memo.merge!(results)
      end
    end

    def self.full_name
      name.split('::').last
    end

    attr_reader :parent, :name, :pending, :dependency_name, :dependencies
    def initialize(name, options = {}, &block)
      @parent = options.delete(:parent)
      @name = name

      @dependency_name = options.delete(:name)
      @dependencies = Array(options.delete(:depends_on))

      initialize_before_hooks(options.delete(:before))

      if block_given?
        instance_eval(&block)
      else
        @pending = true
      end
    end

    def full_name
      parent ? parent.full_name + " " + name : name
    end

    def initialize_before_hooks(hooks)
      Array(hooks).each do |method_name_or_block|
        if method_name_or_block.respond_to?(:call)
          self.before_hooks << method_name_or_block
        elsif respond_to?(method_name_or_block)
          self.before_hooks << method(method_name_or_block)
        end
      end
    end

    def before_hooks
      @before_hooks ||= []
    end

    def new(*args, &block)
      self.class.new(*args, &block)
    end

    def find_shared_example(name)
      ref = self
      begin
        if block = ref.shared_examples[name]
          return block
        end
      end while ref = ref.parent
      self.class.shared_examples[name]
    end

    BehaviourNotFoundError = Class.new(StandardError)
    def behaves_as(name)
      block = find_shared_example(name)
      raise BehaviourNotFoundError.new("Behaviour #{name.inspect} could not be found") unless block
      instance_eval(&block)
    end

    def expectations
      @expectations ||= []
    end

    def expect_response(options = {}, &block)
      expectation = ResponseExpectation.new(self, options, &block)
      self.expectations << expectation
      expectation
    end

    def run
      sort_validations!

      setup_blocks.concat(before_hooks).each do |hook|
        if hook.respond_to?(:receiver) && hook.receiver == self
          # It's a method
          hook.call
        else
          # It's a block
          instance_eval(&hook)
        end
      end

      results = self.expectations.inject([]) do |memo, expectation|
        result = expectation.run
        memo << result if result
        memo
      end

      self.validations.inject(Results.new(self, results)) do |memo, validation|
        memo.merge!(validation.run)
      end
    end

  end
end
