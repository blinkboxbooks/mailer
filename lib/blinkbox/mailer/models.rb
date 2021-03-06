module Blinkbox
  module Mailer
    class Customer < ActionMailer::Base
      layout 'october_launch'

      default from: "blinkbox Books <noreply@blinkboxbooks.com>"

      def welcome(variables = {})
        generate_email variables, "Welcome to blinkbox Books"
      end

      def receipt(variables = {})
        generate_email variables, "Thanks for your purchase from blinkbox Books!"
      end

      def password_confirmed(variables = {})
        generate_email variables, "Your password has been changed"
      end

      def password_reset(variables = {})
        # this mail contains a password reset link which must not be click-tracked!
        generate_email variables, "Resetting your blinkbox Books password is easy", disable_click_tracking: true
      end

      def hudl2_welcome(variables = {})
        generate_email variables, "You're ready to read with your £10 credit"
      end

      private

      def generate_email(variables, default_subject, options = {})
        @variables = Locals.new(variables["templateVariables"])
        cc = prepare_recipient(variables['cc']) rescue nil
        bcc = prepare_recipient(variables['bcc']) rescue nil
        mail(
          to: prepare_recipient(variables['to']),
          cc: cc,
          bcc: bcc,
          subject: variables['subject'] || default_subject,
          from: variables[:email_sender] || default_params[:from]
        ) do |format|
          format.html
          format.text
        end
        message_id = variables.select{ |k,_| k.to_s.include? "messageId"}.first[1]
        headers['X-BBB-Message-Id'] = message_id if message_id
        headers['x-et-route'] = variables[:et_route_key] if variables[:et_route_key]
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