module ApiValidator
  class ResponseExpectation

    require 'api-validator/response_expectation/results'

    attr_accessor :status_validator
    def initialize(validator, options = {}, &block)
      @validator, @block = validator, block
      initialize_headers(options.delete(:headers))
      initialize_status(options.delete(:status))
      initialize_schema(options.delete(:schema))
    end

    def initialize_headers(expected_headers)
      return unless expected_headers
      self.header_validators << ApiValidator::Header.new(expected_headers)
    end

    def initialize_status(expected_status)
      return unless expected_status
      self.status_validator = ApiValidator::Status.new(expected_status)
    end

    def initialize_schema(expected_schema)
      return unless expected_schema
      schema_validators << ApiValidator::JsonSchema.new(expected_schema)
    end

    def json_validators
      @json_validators ||= []
    end

    def schema_validators
      @schema_validators ||= []
    end

    def header_validators
      @header_validators ||= []
    end

    def response_filters
      @response_filters ||= []
    end

    def expectations
      [status_validator].compact + header_validators + schema_validators + json_validators
    end

    def expect_properties(properties)
      json_validators << ApiValidator::Json.new(properties)
    end

    def expect_schema(expected_schema, path=nil)
      schema_validators << ApiValidator::JsonSchema.new(expected_schema, path)
    end

    def expect_headers(expected_headers)
      header_validators << ApiValidator::Header.new(expected_headers)
    end

    def expect_post_type(type_uri)
      response_filters << proc { |response| response.env['expected_post_type'] = type_uri }
      type_uri
    end

    def run
      return unless @block
      response = instance_eval(&@block)
      Results.new(response, validate(response))
    end

    def validate(response)
      response_filters.each { |filter| filter.call(response) }
      expectations.map { |expectation| expectation.validate(response) }
    end

    def respond_to_method_missing?(method)
      @validator.respond_to?(method)
    end

    def method_missing(method, *args, &block)
      if respond_to_method_missing?(method)
        @validator.send(method, *args, &block)
      else
        super
      end
    end

  end
end