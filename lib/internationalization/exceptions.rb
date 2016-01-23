module Internationalization
  class InvalidLocale < ArgumentError
    attr_reader :locale
    def initialize(locale)
      @locale = locale
      super "#{locale.inspect} is not a valid locale"
    end
  end

  class InvalidLocaleData < ArgumentError
    attr_reader :filename
    def initialize(filename, exception_message)
      @filename, @exception_message = filename, exception_message
      super "can not load translations from #{filename}: #{exception_message}"
    end
  end

  class MissingTranslation < ArgumentError
    def initialize(locale, key, options = nil)
      options = options ? options.dup : {}
      @key, @locale, @options = key, locale, options
      options.each { |k, v| self.options[k] = v.inspect if v.is_a?(Proc) }
    end
  end
end
