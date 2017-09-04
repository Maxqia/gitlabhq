module Gitlab
  module EncodingHelper
    extend self

    # This threshold is carefully tweaked to prevent usage of encodings detected
    # by CharlockHolmes with low confidence. If CharlockHolmes confidence is low,
    # we're better off sticking with utf8 encoding.
    # Reason: git diff can return strings with invalid utf8 byte sequences if it
    # truncates a diff in the middle of a multibyte character. In this case
    # CharlockHolmes will try to guess the encoding and will likely suggest an
    # obscure encoding with low confidence.
    # There is a lot more info with this merge request:
    # https://gitlab.com/gitlab-org/gitlab_git/merge_requests/77#note_4754193
    ENCODING_CONFIDENCE_THRESHOLD = 50

    #
    # 
    def encode!(message)
      return nil unless message.respond_to? :force_encoding

      # if message is utf-8 encoding, just return it
      message.force_encoding("UTF-8")
      return message if message.valid_encoding?

      # return message if message type is binary
      detect = CharlockHolmes::EncodingDetector.detect(message)
      return message.force_encoding("BINARY") if all_binary?(message, detect)

      if detect && detect[:encoding] && detect[:confidence] > ENCODING_CONFIDENCE_THRESHOLD
        # force detected encoding if we have sufficient confidence.
        message.force_encoding(detect[:encoding])
      end

      # encode and clean the bad chars
      message.replace clean(message)
    rescue => e
      encoding = detect ? detect[:encoding] : "unknown"
      "--broken encoding: #{encoding}"
    end

    def all_binary?(data, detect=nil)
      detect ||= CharlockHolmes::EncodingDetector.detect(data)
      detect && detect[:type] == :binary
    end

    def libgit2_binary?(data)
      # EncodingDetector checks the first 1024 * 1024 bytes for NUL byte, libgit2 checks
      # only the first 8000 (https://github.com/libgit2/libgit2/blob/2ed855a9e8f9af211e7274021c2264e600c0f86b/src/filter.h#L15),
      # which is what we use below to keep a consistent behavior.
      detect = CharlockHolmes::EncodingDetector.new(8000).detect(data)
      all_binary?(data, detect)
    end

    def encode_utf8(message)
      detect = CharlockHolmes::EncodingDetector.detect(message)
      if detect && detect[:encoding]
        begin
          CharlockHolmes::Converter.convert(message, detect[:encoding], 'UTF-8')
        rescue ArgumentError => e
          Rails.logger.warn("Ignoring error converting #{detect[:encoding]} into UTF8: #{e.message}")

          ''
        end
      else
        clean(message)
      end
    end
      
    private

    def clean(message)
      message.encode("UTF-16BE", undef: :replace, invalid: :replace, replace: "")
        .encode("UTF-8")
        .gsub("\0".encode("UTF-8"), "")
    end
  end
end
