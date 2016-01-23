require "internationalization/version"

module Internationalization; end

Object.send :remove_const, :I18n if defined? I18n

require 'internationalization/exceptions'

module Internationalization
  RESERVED_KEYS = [:scope, :default, :separator, :resolve, :object, :fallback, :format, :cascade, :throw, :raise].freeze

  include ActiveSupport::Configurable

  config_accessor :default_locale do
    :en
  end
  config_accessor :locale
  config_accessor :enforce_available_locales do
    true
  end
  config_accessor :load_path do
    []
  end
  config_accessor :available_locales_set

  class << self
    attr_reader :translations

    def locale
      config.locale || config.default_locale
    end

    # compat
    def backend
      self
    end

    def translate(key, locale: nil, **options)
      locale   ||=  self.locale
      raise InvalidLocale.new(locale) unless locale

      enforce_available_locales!(locale)
      raise I18n::ArgumentError if key == ''

      if key.is_a?(Array)
        key.map { |k| _translate(locale, k, options) }
      else
        _translate(locale, key, options)
      end
    end
    alias :t :translate

    def reload!
      clear_available_locales_set
      @translations = {}
    end

    def locale_available?(locale)
      available_locales_set && available_locales_set.include?(locale)
    end

    def enforce_available_locales!(locale)
      if config.enforce_available_locales && !locale_available?(locale)
        raise I18n::InvalidLocale.new(locale)
      end
    end

    def available_locales
      translations && translations.inject([]) do |locales, (locale, data)|
        locales << locale unless (data.keys - [:i18n]).empty?
        locales
      end
    end

    def load_translations
      load_path.flatten.each { |filename| load_file(filename) }
    end

    def load_file(filename)
      data = YAML.load_file(filename)
      raise InvalidLocaleData.new(filename, 'expects it to return a hash, but does not') unless data.is_a?(Hash)
      data.each { |locale, d| store_translations(locale, d) }
    rescue TypeError, ScriptError, StandardError => e
      raise InvalidLocaleData.new(filename, e.inspect)
    end

    def store_translations(locale, data = {})
      locale = locale.to_sym
      @translations ||= {}
      @translations[locale] ||= {}
      data = data.deep_symbolize_keys
      translations[locale].deep_merge!(data)
    end

    def available_locales_set
      @available_locales_set ||= available_locales && available_locales.inject(Set.new) do |set, locale|
        set << locale.to_s << locale.to_sym
      end
    end

    def clear_available_locales_set
      @available_locales_set = nil
    end

    private
    def _translate(locale, key, scope: nil, count: nil, default: nil, **options)
      entry = key && lookup(locale, key, scope, options)

      if options.empty?
        entry = resolve(locale, key, entry, options)
      else
        values = options.except(*RESERVED_KEYS)
        entry = entry.nil? && default ?
          default(locale, key, default, options) : resolve(locale, key, entry, options)
      end

      raise I18n::MissingTranslation.new(locale, key, options) if entry.nil?
      entry = entry.dup if entry.is_a?(String)

      entry = pluralize(locale, entry, count) if count
      entry = interpolate(locale, entry, values) if values
      entry
    end

    def pluralize(locale, entry, count)
      return entry unless entry.is_a?(Hash) && count

      key = :zero if count == 0 && entry.has_key?(:zero)
      key ||= count == 1 ? :one : :other
      raise InvalidPluralizationData.new(entry, count) unless entry.has_key?(key)
      entry[key]
    end

    def interpolate(string, values)
      raise ReservedInterpolationKey.new($1.to_sym, string) if string =~ RESERVED_KEYS_PATTERN
      raise ArgumentError.new('Interpolation values must be a Hash.') unless values.kind_of?(Hash)
      interpolate_hash(string, values)
    end

    def interpolate_hash(string, values)
      string.gsub(INTERPOLATION_PATTERN) do |match|
        if match == '%%'
          '%'
        else
          key = ($1 || $2).to_sym
          value = if values.key?(key)
                    values[key]
                  else
                    config.missing_interpolation_argument_handler.call(key, values, string)
                  end
          value = value.call(values) if value.respond_to?(:call)
          $3 ? sprintf("%#{$3}", value) : value
        end
      end
    end

    def lookup(locale, key, scope = [], separator: '.', **options)
      byebug
      keys = normalize_keys(locale, key, scope, separator)

      keys.inject(translations) do |result, _key|
        _key = _key.to_sym
        return nil unless result.is_a?(Hash) && result.has_key?(_key)
        result = result[_key]
        result = resolve(locale, _key, result, options.merge(:scope => nil)) if result.is_a?(Symbol)
        result
      end
    end

    def normalize_keys(locale, key, scope, separator = '.')
      keys = []
      keys.concat normalize_key(locale, separator)
      keys.concat normalize_key(scope, separator)
      keys.concat normalize_key(key, separator)
      keys
    end

    def normalize_key(key, separator)
      normalized_key_cache[separator][key] ||=
        case key
        when Array
          key.map { |k| normalize_key(k, separator) }.flatten
        else
          keys = key.to_s.split(separator)
          keys.delete('')
          keys.map! { |k| k.to_sym }
          keys
        end
    end

    def normalized_key_cache
      @normalized_key_cache ||= Hash.new { |h,k| h[k] = {} }
    end

    def resolve(locale, object, subject, options = {})
      case subject
      when Symbol
        I18n.translate(subject, options.merge(locale: locale))
      when Proc
        date_or_time = options.delete(:object) || object
        resolve(locale, object, subject.call(date_or_time, options))
      else
        subject
      end
    end
  end
#   load_translations

  class Config; end
end

I18n = Internationalization
load 'active_support/i18n_railtie.rb'
