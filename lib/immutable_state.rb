# frozen_string_literal: true

require 'immutable_state/version'
require 'contracts'

# Immutable data structure with typed fields and invariants.
module ImmutableState
  CONFIG_CLASS_VARIABLE     = :@@immutable_state_config
  INVARIANTS_CLASS_VARIABLE = :@@immutable_state_invariants

  module Errors
    class Base < StandardError; end

    class DuplicateConfig       < Base; end
    class InvalidInvariant      < Base; end
    class DuplicateInvariant    < Base; end
    class InvalidValue          < Base; end
    class InvariantBroken       < Base; end
    class InvalidInitialization < Base; end

    class InvalidConfig         < Base; end
    class InvalidContract       < Base; end
  end

  # Class-level methods of ImmutableState
  module ClassMethods
    include Contracts::Core
    C = Contracts

    Contract C::HashOf[Symbol => C::Any]
    def immutable_state_config
      class_variable_get CONFIG_CLASS_VARIABLE
    end

    Contract C::HashOf[Symbol => C::Any] => :ok
    def immutable_state(config)
      raise Errors::DuplicateConfig unless immutable_state_config.empty?

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
      raise Errors::InvalidInvariant unless block.is_a? Proc
      raise Errors::InvalidInvariant unless name.is_a?(String) && !name.empty?

      state_invariants = class_variable_get INVARIANTS_CLASS_VARIABLE
      raise Errors::DuplicateInvariant if state_invariants.keys.include? name

      state_invariants[name] = block

      :ok
    end
  end

  # Instance-level methods of ImmutableState
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

      if invalid_keys.any?
        raise Errors::InvalidInitialization,
              "There are unexpected entries in initialization hash: #{invalid_keys.join(', ')}"
      end

      hash.each do |key, value|
        instance_variable_set "@#{key}".to_sym, value
      end

      Util.value_checking      self
      Util.invariants_checking self
    end

    def next_state
      ns = to_h

      yield(ns)

      self.class.new(ns)
    end
  end

  # Utility methods for ImmutableState.
  module Util
    class << self
      include Contracts::Core
      C = Contracts

      Contract ImmutableState => :ok
      def value_checking(state)
        state.immutable_state_config.each do |key, contract|
          var_name = "@#{key}".to_sym
          value    = state.instance_variable_get var_name

          raise Errors::InvalidValue, "Invalid contract for #{key}: #{contract}" unless Contract.valid?(value, contract)
        end

        :ok
      end

      Contract ImmutableState => :ok
      def invariants_checking(state)
        state.immutable_state_invariants.each do |name, invariant|
          result = state.instance_exec(&invariant)

          raise Errors::InvariantBroken, "Invariant #{name} broken." unless result
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
