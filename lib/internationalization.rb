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
    attr_internal_writer :config

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
      if enforce_available_locales && !locale_available?(locale)
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
      load_path.flatten.each {|filename| load_file(filename)}
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
      data = flatten_hash data
      data = resolve_symbols data
      translations[locale].merge! data
    end

    def flatten_hash(hash)
      ret = {}
      paths = hash.keys.map {|k| [k]}

      until paths.empty?
        path = paths.shift
        value = hash
        path.each {|step| value = value[step]}

        if value.respond_to? :keys
          value.keys.each {|k| paths << path + [k]}
        else
          ret[path.join('.')] = value
        end
      end

      ret
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

    def lookup(locale, key, scope = [], **options)
      key = normalize_keys(locale, key, scope)

      result = translations[locale][key]
      result = resolve(locale, key, result, options.merge(scope: nil))
      result
    end

    def normalize_keys(locale, key, scope)
      if !scope || scope.empty?
        normalize_key(key)
      else
        [normalize_key(scope), normalize_key(key)].join('.')
      end
    end

    def normalize_key(key)
      case key
      when Array
        key.join('.')
      else
        key.to_s
      end
    end

    def resolve(locale, object, subject, options = {})
      if subject.is_a? Proc
        date_or_time = options.delete(:object) || object
        resolve(locale, object, subject.call(date_or_time, options))
      else
        subject
      end
    end

    def resolve_symbols(hash)
      hash.each_pair do |k, v|
        if v.is_a? Symbol
          hash[k] = hash[v]
        end
      end
      hash = resolve_symbols hash if hash.values.any? {|v| v.is_a? Symbol}
      hash
    end
  end
#   load_translations

  class Config; end

  def @_config.respond_to_missing?(name, include_private)
    keys.include? name
  end
end

I18n = Internationalization
p 'loading AS/i18n_railtie...'
load 'active_support/i18n_railtie.rb'
