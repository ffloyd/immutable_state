require "immutable_state/version"
require "contracts"

module ImmutableState
  CONFIG_CLASS_VARIABLE = :@@immutable_state_config
  CC_CLASS_VARIABLE     = :@@consistency_check_lambda

  module Error
    class InvalidConfig         < StandardError; end
    class InvalidInitialization < StandardError; end
    class InvalidContract       < StandardError; end
    class InvalidValue          < StandardError; end
    class InconsistentState     < StandardError; end
  end

  module ClassMethods
    include Contracts::Core
    C = Contracts

    def immutable_state_config
      class_variable_get CONFIG_CLASS_VARIABLE
    end

    Contract C::HashOf[Symbol => C::Any] => :ok
    def immutable_state(config)
      class_variable_set CONFIG_CLASS_VARIABLE, config

      config.keys.each do |key|
        attr_reader key
      end
      :ok
    end

    def consistency_check_lambda
      class_variable_get CC_CLASS_VARIABLE
    end

    def consistency_check(&block)
      raise TypeError unless block.is_a? Proc
      class_variable_set CC_CLASS_VARIABLE, block
      :ok
    end
  end

  module InstanceMethods
    include Contracts::Core
    C = Contracts

    def immutable_state_config
      self.class.immutable_state_config
    end

    def consistency_check_lambda
      self.class.consistency_check_lambda
    end

    private

    def state_from_hash(hash)
      invalid_keys = hash.keys - immutable_state_config.keys

      raise Error::InvalidInitialization,
            "There are unexpected entries in initialization hash: #{invalid_keys.join(', ')}" if invalid_keys.any?

      hash.each do |key, value|
        var_name = "@#{key}".to_sym

        instance_variable_set var_name, value
      end

      Util.value_checking       self
      Util.consistency_checking self
    end
  end

  module Util
    class << self
      def value_checking(state)
        state.immutable_state_config.each do |key, contract|
          var_name = "@#{key}".to_sym
          value    = state.instance_variable_get var_name

          raise Error::InvalidValue, "Invalid contract for #{key}: #{contract}" unless Contract.valid?(value, contract)
        end
      end

      def consistency_checking(state)
        lambda = state.consistency_check_lambda
        errors = []

        state.instance_exec(errors, &lambda)

        raise Error::InconsistentState if errors.any?
      end
    end
  end

  def self.included(mod)
    mod.class_variable_set CONFIG_CLASS_VARIABLE, {}
    mod.class_variable_set CC_CLASS_VARIABLE, ->(_) {}

    mod.extend  ::ImmutableState::ClassMethods
    mod.include ::ImmutableState::InstanceMethods
  end
end
