# A Pipeline emitter is an active record model that, when changed,
# will publish the changed fields to some sort of queue

require_relative "./symmetric_encryptor"

module RailsPipeline
  module Emitter
    include RailsPipeline::SymmetricEncryptor

    def self.included(base)
      # doing an include SymmetricEncryptor doesn't pull this in where I'd like it
      base.extend RailsPipeline::SymmetricEncryptor::ClassMethods
      base.send :include, InstanceMethods
      base.extend ClassMethods
      base.after_save :emit
    end

    module InstanceMethods
      def emit
        self.class.pipeline_versions.each do |version|
          topic = self.class.topic_name(version)
          RailsPipeline.logger.debug "Emitting to #{topic}"
          data = self.send("to_pipeline_#{version}")
          data["pipeline_version"] = version
          enc_data = self.class.symmetric_encrypt(data)
          self.publish(topic, enc_data)
        end
      end

      # Default v1.0 emitter: emit all fields.
      def to_pipeline_1_0
        attributes
      end
    end

    module ClassMethods
      # Get the list of versions to emit (all that are implemented, basically)
      def pipeline_versions
        versions = []
        pipeline_methods = instance_methods.grep(/^to_pipeline/).sort
        pipeline_methods.each do |pipeline_method|
          version = pipeline_method.to_s.gsub("to_pipeline_", "")
          if version.starts_with?("1_") && version != "1_0"
            # Delete the default v1.0 emitter if a later v1 emitter is defined
            i = versions.index("1_0")
            versions.delete_at(i) if !i.nil?
          end
          versions << version
        end
        return versions
      end

      # Get pub/sub topic name to which changes to this model will be published
      def topic_name(version="1_0")
        return "harrys-#{Rails.env}-v#{major(version)}-#{table_name}"
      end

      # Get the major version number from a "1_1" style major/minor version string
      def major(version)
        if version.include? '_'
          major, _ = version.split('_', 2)
        else
          major = version
        end
        return major
      end

      def _secret
        ENV.fetch("PIPELINE_SECRET", Rails.application.config.secret_token)
      end

    end
  end


end
