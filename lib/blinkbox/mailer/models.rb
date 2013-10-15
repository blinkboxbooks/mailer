module Blinkbox
  module Mailer
    class Customer < ActionMailer::Base
      layout 'october_launch'

      default from: "blinkbox books <noreply@blinkboxbooks.com>"

      def welcome(variables = {})
        generate_email variables, "Welcome to blinkbox books"
      end

      def receipt(variables = {})
        generate_email variables, "Thank you for choosing blinkbox books"
      end

      def password_confirmed(variables = {})
        generate_email variables, "Password change confirmation for your blinkbox books account"
      end

      def password_reset(variables = {})
        # this mail contains a password reset link which must not be click-tracked!
        generate_email variables, "Password reset for your blinkbox books account", disable_click_tracking: true
      end

      private

      def generate_email(variables, default_subject, options = {})
        @variables = Locals.new(variables["templateVariables"])
        mail(
          to: prepare_recipient(variables['to']),
          subject: variables['subject'] || default_subject
        ) do |format|
          format.html
          format.text
        end
        message_id = variables.select{ |k,v| k.include? ":messageId"}[0]
        headers['X-BBB-Message-Id'] = message_id if message_id

        # see http://help.mandrill.com/entries/21688056-Using-SMTP-Headers-to-customize-your-messages
        headers['X-MC-Track'] = 'open' if options[:disable_click_tracking]
      end

      def prepare_recipient(recipients)
        recipients.collect do |recipient|
          if recipient['name'].nil? || recipient['name'].empty?
            recipient['email']
          else
            "\"#{recipient['name']}\" <#{recipient['email']}>"
          end
        end
      end
    end

    class Locals
      def initialize(hash)
        @hash = hash
      end

      def method_missing(m)
        raise ArgumentError, "The variable '#{m}' is not available" unless @hash.has_key?(m.to_s)
        @hash[m.to_s]
      end
    end
  end
end