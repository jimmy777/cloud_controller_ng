require 'repositories/runtime/package_event_repository'

module VCAP::CloudController
  class PackageUploadMessage
    attr_reader :package_path, :package_guid

    def initialize(package_guid, opts)
      @package_guid = package_guid
      @package_path = opts['bits_path']
    end

    def validate
      return false, 'An application zip file must be uploaded.' unless @package_path
      true
    end
  end

  class PackageCreateMessage
    attr_reader :app_guid, :type, :url
    attr_accessor :error
    def self.create_from_http_request(app_guid, body)
      opts = body && MultiJson.load(body)
      raise MultiJson::ParseError.new('invalid request body') unless opts.is_a?(Hash)
      PackageCreateMessage.new(app_guid, opts)
    rescue MultiJson::ParseError => e
      message = PackageCreateMessage.new(app_guid, {})
      message.error = e.message
      message
    end

    def initialize(app_guid, opts)
      @app_guid = app_guid
      @type     = opts['type']
      @url      = opts['url']
    end

    def validate
      return false, [error] if error
      errors = []
      errors << validate_type_field
      errors << validate_url
      errs = errors.compact
      [errs.length == 0, errs]
    end

    private

    def validate_type_field
      return 'The type field is required' if @type.nil?
      valid_type_fields = PackageModel::PACKAGE_TYPES

      if !valid_type_fields.include?(@type)
        return "The type field needs to be one of '#{valid_type_fields.join(', ')}'"
      end
      nil
    end

    def validate_url
      return 'The url field cannot be provided when type is bits.' if @type == 'bits' && !@url.nil?
      return 'The url field must be provided for type docker.' if @type == 'docker' && @url.nil?
      nil
    end
  end

  class PackagesHandler
    class Unauthorized < StandardError; end
    class InvalidPackageType < StandardError; end
    class InvalidPackage < StandardError; end
    class AppNotFound < StandardError; end
    class SpaceNotFound < StandardError; end
    class PackageNotFound < StandardError; end
    class BitsAlreadyUploaded < StandardError; end

    def initialize(config, paginator=SequelPaginator.new)
      @config    = config
      @paginator = paginator
    end

    def list(pagination_options, access_context, filter_options={})
      dataset = nil
      if access_context.roles.admin?
        dataset = PackageModel.dataset
      else
        dataset = PackageModel.user_visible(access_context.user)
      end

      dataset = dataset.where(app_guid: filter_options[:app_guid]) if filter_options[:app_guid]

      @paginator.get_page(dataset, pagination_options)
    end

    def create(message, access_context)
      package          = PackageModel.new
      package.app_guid = message.app_guid
      package.type     = message.type
      package.url      = message.url
      package.state    = message.type == 'bits' ? PackageModel::CREATED_STATE : PackageModel::READY_STATE

      app_model = AppModel.find(guid: package.app_guid)
      raise AppNotFound if app_model.nil?
      space = Space.find(guid: app_model.space_guid)
      raise SpaceNotFound if space.nil?

      raise Unauthorized if access_context.cannot?(:create, package, space)
      package.save

      Repositories::Runtime::PackageEventRepository.record_app_add_package(
        package,
        access_context.user,
        access_context.user_email,
        message.as_json
      )

      package
    rescue Sequel::ValidationFailed => e
      raise InvalidPackage.new(e.message)
    end

    def upload(message, access_context)
      package = PackageModel.find(guid: message.package_guid)

      raise PackageNotFound if package.nil?
      raise InvalidPackageType.new('Package type must be bits.') if package.type != 'bits'
      raise BitsAlreadyUploaded.new('Bits may be uploaded only once. Create a new package to upload different bits.') if package.state != PackageModel::CREATED_STATE

      app_model = AppModel.find(guid: package.app_guid)
      raise AppNotFound if app_model.nil?
      space = Space.find(guid: app_model.space_guid)
      raise SpaceNotFound if space.nil?

      raise Unauthorized if access_context.cannot?(:create, package, space)

      package.update(state: PackageModel::PENDING_STATE)

      bits_upload_job = Jobs::Runtime::PackageBits.new(package.guid, message.package_path)
      Jobs::Enqueuer.new(bits_upload_job, queue: Jobs::LocalQueue.new(@config)).enqueue

      package
    end

    def show(guid, access_context)
      package = PackageModel.find(guid: guid)
      return nil if package.nil?
      raise Unauthorized if access_context.cannot?(:read, package)
      package
    end
  end
end
