describe KnapsackPro::TestFileCleaner do
  describe '.clean' do
    subject { described_class.clean(test_file_path) }

    context 'when the test file path starts with ./' do
      let(:test_file_path) { './models/user_spec.rb' }

      it 'removes ./ from the begining of the test file path' do
        expect(subject).to eq 'models/user_spec.rb'
      end
    end

    context 'when the test file path does not start with ./' do
      let(:test_file_path) { 'models/user_spec.rb' }

      it 'returns the test file path unchanged' do
        expect(subject).to eq 'models/user_spec.rb'
      end
    end

    context 'when the test file path contains ./ somewhere else' do
      let(:test_file_path) { 'models/./user_spec.rb' }

      it 'only removes the prefix' do
        expect(subject).to eq 'models/./user_spec.rb'
      end
    end

    context 'when the test file path is an id path' do
      let(:test_file_path) { './models/user_spec.rb[1:1]' }

      it 'removes ./ from the begining of the test file path' do
        expect(subject).to eq 'models/user_spec.rb[1:1]'
      end
    end
  end
end
