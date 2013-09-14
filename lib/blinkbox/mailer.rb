require_relative 'mailer/env'
require_relative 'mailer/models'
require 'bunny'
require 'multi_json'
require 'digest/sha1'
require 'uri'
require 'fileutils'

module Blinkbox
  module Mailer
    class Daemon
      def initialize(options)
        @log = options['logger']

        @log.debug "Opening connection to message queue"
        @amqp = { :connection => Bunny.new(options[:mq] || "amqp://guest:guest@127.0.0.1:5672") }
        @amqp[:connection].start
        @log.debug "Opening message channel"
        @amqp[:channel] = @amqp[:connection].create_channel

        @amqp[:channel].prefetch(50)

        ActionMailer::Base.smtp_settings = {
          :address   => options[:smtp_server],
          :port      => options[:smtp_port],
          :authentication => :plain,
          :user_name      => options[:smtp_username],
          :password       => options[:smtp_password],
          :enable_starttls_auto => true
        }

        @resource_server = {
          :write => options[:resource_server_write],
          :http => options[:resource_server_http]
        }
      end

      def start
        @log.info "Listening for email instruction messages"
        queue = @amqp[:channel].queue("Emails.Outbound",
          :durable => true,
          :arguments => {
            "x-dead-letter-exchange" => "Emails.Outbound.DLX"
          }
        )

        queue.subscribe(ack: true, block: true) do |delivery_info, metadata, payload|
          begin
            @log.info "Received message (##{delivery_info.delivery_tag})"
            json = MultiJson.load(payload)

            raise RuntimeError, "No recipient specified" unless json['to']

            unless Blinkbox::Mailer::Customer.action_methods.include? json['template']
              raise RuntimeError, "No such email template '#{json['template']}'"
            end

            root_folder = ["mails"]
            root_folder.unshift("user:#{json["restrict_view_to_user"]}") if json["restrict_view_to_user"]

            view_online_path = File.join(*(root_folder + Digest::SHA1.hexdigest(json.inspect).scan(/.{4}/))) + ".html"

            local_filename = File.join(@resource_server[:write],view_online_path)
            json['view_online_url'] = File.join(@resource_server[:http],view_online_path)

            email = Blinkbox::Mailer::Customer.send(json['template'], json)

            unless File.directory?(File.dirname(local_filename))
              @log.debug "Making directory #{File.dirname(local_filename)}"
              FileUtils.mkdir_p(File.dirname(local_filename))
            end

            open(local_filename,'w') do |f|
              f.write email.html_part.body
            end

            email.deliver

            @amqp[:channel].acknowledge(delivery_info.delivery_tag, false)
            @log.info "Email delivered (##{delivery_info.delivery_tag})"

          rescue ActionView::Template::Error => e
            @amqp[:channel].nack(delivery_info.delivery_tag, false)
            @log.error "#{e.message} in the message (##{delivery_info.delivery_tag}) so it was rejected back to the queue"

          rescue MultiJson::LoadError
            @amqp[:channel].nack(delivery_info.delivery_tag, false)
            @log.error "The incoming message (##{delivery_info.delivery_tag}) was incorrectly formed and was rejected back to the queue "

          rescue Exception => e
            @amqp[:channel].nack(delivery_info.delivery_tag, false)
            @log.error "Failure to process message (##{delivery_info.delivery_tag}), rejected back to queue (#{e.message})"
            @log.debug "#{e.class}: #{e.message}\n\t#{e.backtrace.join("\n\t")}"
          end
        end
      end

      def stop
        @amqp[:channel].close
        @amqp[:connection].close
      end
    end
  end
end