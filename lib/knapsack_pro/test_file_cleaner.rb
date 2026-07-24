# frozen_string_literal: true

module KnapsackPro
  class TestFileCleaner
    PREFIX = './'

    # Called for every test example, so avoid allocating a new String when
    # there is no `./` prefix to remove (the common case).
    def self.clean(test_file_path)
      return test_file_path unless test_file_path.start_with?(PREFIX)

      test_file_path.delete_prefix(PREFIX)
    end
  end
end
