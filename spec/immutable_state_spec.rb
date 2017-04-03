# frozen_string_literal: true

require 'spec_helper'
require 'pry' # for debugging via binding.pry

RSpec.shared_context 'without config' do
  let(:klass) do
    Class.new do
      include ImmutableState
    end
  end

  let(:instance) { klass.new }
end

RSpec.shared_context 'xy-point state' do
  let(:klass) do
    Class.new do
      include ImmutableState

      immutable_state x: Integer,
                      y: Integer

      def initialize(hash = {})
        state_from_hash(hash)
      end
    end
  end

  let(:initial_value) do
    { x: 1, y: 2 }
  end

  let(:instance) { klass.new(initial_value) }
end

RSpec.shared_context 'shared sum state' do
  let(:klass) do
    Class.new do
      include ImmutableState

      immutable_state total:   Contracts::Pos,
                      share_a: Contracts::Pos,
                      share_b: Contracts::Pos

      state_invariant 'Shares sum must be equal to total' do
        share_a + share_b == total
      end

      def initialize(hash = {})
        state_from_hash(hash)
      end
    end
  end

  let(:initial_value) do
    { total: 100, share_a: 60, share_b: 40 }
  end

  let(:instance) { klass.new(initial_value) }
end

RSpec.describe ImmutableState do
  it 'has a version number' do
    expect(ImmutableState::VERSION).not_to be nil
  end

  describe '.immutable_state_config & #immutable_state_config' do
    def is_expected_to_eq(val)
      expect(instance.immutable_state_config).to eq val
      expect(klass.immutable_state_config).to    eq val
    end

    context 'for state without config' do
      include_context 'without config'

      it { is_expected_to_eq({}) }
    end

    context 'for state with defined config' do
      include_context 'xy-point state'

      it 'returns config' do
        is_expected_to_eq(x: Integer, y: Integer)
      end
    end
  end

  describe '.immutable_state_invariants & #immutable_state_invariants' do
    def is_expected_to_eq(val)
      expect(instance.immutable_state_invariants).to eq val
      expect(klass.immutable_state_invariants).to    eq val
    end

    context 'for state without config' do
      include_context 'without config'

      it { is_expected_to_eq({}) }
    end
  end

  describe '.immutable_state' do
    subject(:apply_config) { klass.immutable_state config }

    let(:config) do
      {
        int: Integer,             # class contract
        pos: Contracts::Pos,      # built-in contract from contracts.ruby
        odd: ->(val) { val.odd? } # lambda-form contract
      }
    end

    context 'when no config defined yet' do
      include_context 'without config'

      it 'setups given config' do
        expect { apply_config }.to change(klass, :immutable_state_config).from({}).to(config)
      end

      def readers_present?
        config.keys.inject(true) { |a, e| a && instance.respond_to?(e) }
      end

      it 'creates attr_readers for fields' do
        expect { apply_config }.to change { readers_present? }.from(false).to(true)
      end
    end

    context 'with invalid config' do
      include_context 'without config'

      let(:config) { { 'invalid' => 'data' } }

      it { expect { apply_config }.to raise_error ParamContractError }
    end

    context 'when config already defined' do
      include_context 'xy-point state'

      it { expect { apply_config }.to raise_error ImmutableState::Errors::DuplicateConfig }
    end
  end

  describe '.state_invariant' do
    subject(:add_invariant) { klass.state_invariant(name, &lambda) }

    let(:name)   { 'Unbreakable invariant' }
    let(:lambda) { -> { true } }

    context 'for state without invariants' do
      include_context 'xy-point state'

      it 'adds first invariant' do
        expect { add_invariant }.to change(instance, :immutable_state_invariants)
          .from({})
          .to(name => lambda)
      end
    end

    context 'for state with invariant' do
      include_context 'shared sum state'

      let!(:invariants_before) { klass.immutable_state_invariants }

      it 'adds invariant and keeps older ones' do
        expect { add_invariant }.to change(instance, :immutable_state_invariants)
          .to(invariants_before.merge(name => lambda))
      end
    end

    context 'when block is missing' do
      subject(:add_invariant) { klass.state_invariant(name) }

      include_context 'xy-point state'

      it 'raises InvalidInvariant error' do
        expect { add_invariant }.to raise_error ImmutableState::Errors::InvalidInvariant
      end
    end

    context 'when name is not a String' do
      include_context 'xy-point state'

      let(:name) { :unexpected_symbol }

      it 'raises InvalidInvariant error' do
        expect { add_invariant }.to raise_error ImmutableState::Errors::InvalidInvariant
      end
    end

    context 'when name is already used' do
      include_context 'shared sum state'

      let(:name) { klass.immutable_state_invariants.keys.first }

      it 'raises DuplicateInvariant error' do
        expect { add_invariant }.to raise_error ImmutableState::Errors::DuplicateInvariant
      end
    end
  end

  describe '#to_h' do
    subject { instance.to_h }

    context 'for state without config' do
      include_context 'without config'

      it { is_expected.to eq({}) }
    end

    context 'for state with config' do
      include_context 'xy-point state'

      it 'returns hash equals to initialization hash' do
        is_expected.to eq initial_value
      end
    end
  end

  describe '#state_from_hash (private)' do
    subject(:call_via_new) { instance }

    context 'when all data is correct' do
      include_context 'xy-point state'

      it 'executes without errors' do
        expect { call_via_new }.not_to raise_error
      end
    end

    context 'when contract on one field broken' do
      include_context 'xy-point state'

      let(:initial_value) do
        {
          x: "i'm supposed to be an Integer",
          y: 2
        }
      end

      it 'raises InvalidValue error' do
        expect { call_via_new }.to raise_error ImmutableState::Errors::InvalidValue
      end
    end

    context 'when invariant broken' do
      include_context 'shared sum state'

      let(:initial_value) do
        { total: 100, share_a: 100, share_b: 100 }
      end

      it 'raises InvariantBroken error' do
        expect { call_via_new }.to raise_error ImmutableState::Errors::InvariantBroken
      end
    end
  end

  describe '#next_state (private)' do
    subject(:call_via_send) do
      extracted_lambda = argument
      instance.send :next_state, &extracted_lambda
    end

    let(:argument) do
      lambda do |ns|
        # do something when override me
      end
    end

    context 'when no changes made' do
      include_context 'xy-point state'

      it 'returns state with similar values' do
        expect(call_via_send.to_h).to eq instance.to_h
      end
    end

    context 'when changes are correct' do
      include_context 'xy-point state'

      let(:argument) do
        lambda do |ns|
          ns[:x] = 10
        end
      end

      it 'returns state with modified values' do
        expect(call_via_send.to_h).to eq(x: 10, y: 2)
      end
    end

    context 'when changes has invalid value' do
      include_context 'xy-point state'

      let(:argument) do
        lambda do |ns|
          ns[:x] = 'Why I am a String?'
        end
      end

      it 'raises InvalidValue error' do
        expect { call_via_send }.to raise_error ImmutableState::Errors::InvalidValue
      end
    end

    context 'when changes define invalid key' do
      include_context 'xy-point state'

      let(:argument) do
        lambda do |ns|
          ns[:z] = 3
        end
      end

      it 'raises InvalidInitialization error' do
        expect { call_via_send }.to raise_error ImmutableState::Errors::InvalidInitialization
      end
    end

    context 'when changes break invariant' do
      include_context 'shared sum state'

      let(:argument) do
        lambda do |ns|
          ns[:share_a] = 100
        end
      end

      it 'raises InvariantBroken error' do
        expect { call_via_send }.to raise_error ImmutableState::Errors::InvariantBroken
      end
    end
  end
end
