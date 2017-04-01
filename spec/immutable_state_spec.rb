require "spec_helper"

RSpec.describe ImmutableState do
  it "has a version number" do
    expect(ImmutableState::VERSION).not_to be nil
  end

  let(:klass_without_config) do
    Class.new do
      include ImmutableState
    end
  end

  let(:state_config) do
    {
      x: Integer,
      y: Integer
    }
  end

  let(:default_state) do
    {
      x: 1,
      y: 2
    }
  end

  let(:klass) do
    # 2 strings of shamanism
    state_config  = self.state_config
    default_state = self.default_state

    Class.new do
      include ImmutableState

      immutable_state state_config

      @default_state = default_state # another shaman string

      def initialize
        hash = self.class.instance_variable_get :@default_state # last accord of shamanism
        state_from_hash hash
      end
    end
  end

  let(:instance) do
    klass.new
  end

  describe '.immutable_state_config & #immutable_state_config' do
    def is_expected_to_eq(value)
      klass    = subject
      instance = subject.new

      expect(klass.immutable_state_config).to    eq value
      expect(instance.immutable_state_config).to eq value
    end

    context 'when no config provided' do
      subject { klass_without_config }

      it { is_expected_to_eq({}) }
    end

    context 'when simple config provided (xy-point)' do
      subject { klass }

      it { is_expected_to_eq state_config }
    end
  end

  describe '.immutable_state' do
    context 'with simple config (xy-point)' do
      it 'creates readers' do
        expect(instance).to respond_to :x
        expect(instance).to respond_to :y
      end
    end

    context 'with config based on contracts' do
      let(:state_config) do
        {
          x: Contracts::Pos,
          y: Contracts::Pos
        }
      end

      it 'positive value checking scenario works' do
        expect { instance }.to_not raise_error
      end

      context 'and invalid values' do
        let(:default_state) do
          {
            x: -1,
            y: -2
          }
        end

        it { expect { instance }.to raise_error ImmutableState::Error::InvalidValue }
      end
    end

    context 'with invalid config key type' do
      let(:state_config) do
        {
          'x'   => Integer,
          'fff' => Integer
        }
      end

      it { expect { instance }.to raise_error ParamContractError }
    end
  end

  describe '#state_from_hash (private)' do
    subject { instance }

    context 'when correct' do
      it 'initializes without errors' do
        expect { subject }.to_not raise_error
      end

      it 'sets values' do
        expect(subject.x).to eq default_state[:x]
        expect(subject.y).to eq default_state[:y]
      end
    end

    context 'when unexpected key present' do
      let(:default_state) do
        {
          x: 1,
          y: 2,
          z: 3 # it's an unexpected one
        }
      end

      it 'raises ImmutableState::Error::InvalidInitialization' do
        expect { subject }.to raise_error ImmutableState::Error::InvalidInitialization
      end
    end

    context 'when contract broken' do
      let(:default_state) do
        {
          x: 'i should be an Integer',
          y: 2
        }
      end

      it { expect { subject }.to raise_error ImmutableState::Error::InvalidValue }
    end
  end
end
