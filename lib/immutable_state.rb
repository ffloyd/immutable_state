require "immutable_state/version"
require "contracts"

module ImmutableState
  CONFIG_CLASS_VARIABLE     = :@@immutable_state_config
  INVARIANTS_CLASS_VARIABLE = :@@immutable_state_invariants

  module Error
    class Base < StandardError; end

    class InvalidConfig         < Base; end
    class InvalidInitialization < Base; end
    class InvalidContract       < Base; end
    class InvalidValue          < Base; end
    class InvariantBroken       < Base; end
  end

  module ClassMethods
    include Contracts::Core
    C = Contracts

    Contract C::HashOf[Symbol => C::Any]
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

    def immutable_state_invariants
      class_variable_get INVARIANTS_CLASS_VARIABLE
    end

    def state_invariant(name, &block)
      state_invariants       = class_variable_get INVARIANTS_CLASS_VARIABLE
      state_invariants[name] = block

      :ok
    end
  end

  module InstanceMethods
    include Contracts::Core
    C = Contracts

    Contract C::HashOf[Symbol => C::Any]
    def immutable_state_config
      self.class.immutable_state_config
    end

    def immutable_state_invariants
      self.class.immutable_state_invariants
    end

    Contract C::HashOf[Symbol => C::Any]
    def to_h
      Hash[
        immutable_state_config.map do |field, _contract|
          var_name = "@#{field}".to_sym

          [field, instance_variable_get(var_name)]
        end
      ]
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

      Util.value_checking      self
      Util.invariants_checking self
    end

    def next_state(&block)
      ns = to_h

      block.call(ns)

      self.class.new(ns)
    end
  end

  module Util
    class << self
      include Contracts::Core
      C = Contracts

      Contract ImmutableState => :ok
      def value_checking(state)
        state.immutable_state_config.each do |key, contract|
          var_name = "@#{key}".to_sym
          value    = state.instance_variable_get var_name

          raise Error::InvalidValue, "Invalid contract for #{key}: #{contract}" unless Contract.valid?(value, contract)
        end

        :ok
      end

      Contract ImmutableState => :ok
      def invariants_checking(state)
        state.immutable_state_invariants.each do |name, invariant|
          result = state.instance_exec(&invariant)

          raise Error::InvariantBroken, "Invariant #{name} broken." unless result
        end

        :ok
      end
    end
  end

  def self.included(mod)
    mod.class_variable_set CONFIG_CLASS_VARIABLE,     {}
    mod.class_variable_set INVARIANTS_CLASS_VARIABLE, {}

    mod.extend  ::ImmutableState::ClassMethods
    mod.include ::ImmutableState::InstanceMethods
  end
end
