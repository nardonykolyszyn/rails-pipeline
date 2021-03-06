require 'base64'
require 'json'

module RailsPipeline
    class IronmqPullingSubscriber
        include RailsPipeline::Subscriber

        attr_reader :queue_name

        def initialize(queue_name)
            @queue_name  = queue_name
            @subscription_status = false
        end

        # Valid Parameters at this time are 
        # wait_time - An integer indicating how long in seconds we should long poll on empty queues
        # halt_on_error - A boolean indicating if we should stop our queue subscription if an error occurs
        def start_subscription(params={wait_time: 2, halt_on_error: true}, &block)
            activate_subscription

            while active_subscription?
                pull_message(params[:wait_time]) do |message|
                    process_message(message, params[:halt_on_error], block)
                end
            end
        end


        def process_message(message, halt_on_error, block)
            begin
                if message.nil? || JSON.parse(message.body).empty?
                    deactivate_subscription
                else
                    payload = parse_ironmq_payload(message.body)
                    envelope = generate_envelope(payload)

                    process_envelope(envelope, message, block)
                end
            rescue Exception => e
                if halt_on_error
                    deactivate_subscription
                end

                RailsPipeline.logger.error "A message was unable to be processed as was not removed from the queue."
                RailsPipeline.logger.error "The message: #{message.inspect}"
                raise e
            end
        end

        def active_subscription?
            @subscription_status
        end

        def activate_subscription
            @subscription_status = true
        end

        def deactivate_subscription
            @subscription_status = false
        end

        def process_envelope(envelope, message, block)
            callback_status = block.call(envelope)

            if callback_status
                message.delete
            end
        end


        #the wait time on this may need to be changed
        #haven't seen rate limit info on these calls but didnt look
        #all that hard either.
        def pull_message(wait_time)
            queue = _iron.queue(queue_name)
            yield queue.get(:wait => wait_time)
        end

        private

        def _iron
            @iron = IronMQ::Client.new if @iron.nil?
            return @iron
        end

        def parse_ironmq_payload(message_body)
            payload = JSON.parse(message_body)["payload"]
            Base64.strict_decode64(payload)
        end

        def generate_envelope(payload)
            RailsPipeline::EncryptedMessage.parse(payload)
        end

    end
end
