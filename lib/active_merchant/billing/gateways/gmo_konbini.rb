#encoding: utf-8
require File.dirname(__FILE__) + '/gmo/gmo_errors'
require File.dirname(__FILE__) + '/gmo/gmo_common'

module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class GmoKonbiniGateway < GmoCommon
      include GmoErrors

      JST = "+0900"

      self.supported_countries = ['JA']
      self.homepage_url = 'http://www.gmo-pg.jp/'
      self.display_name = 'GMO Konbini'

      def initialize(options = {})
        requires!(options, :shop_id, :password, :shop_name, :shop_phone, :shop_hours)
        @shop_name = encode_shift_jis(options[:shop_name])
        @shop_phone = options[:shop_phone]
        @shop_hours = options[:shop_hours]
        super
      end

      def capture(*args)
        Response.new true, 'Success', {}, { test: test? }
      end

      def prepare( money, order_id )
        post = {}

        add_money( post, money )
        add_order( post, order_id )

        commit 'prepare', post
      end

      def self.supported_cardtypes
        [:konbini]
      end

      def authorize(money, konbini, options = {})
        requires!(options, :order_id)
        requires!(options, :billing_address)
        requires!(options[:billing_address], :kana)

        unless konbini && konbini.convenience_id
          return Response.new false, 'no convenience store selected', {}, { test: test? }
        end

        if options[:billing_address][:kana].blank?
          return Response.new false, 'kana not specified', {}, { test: test? }
        end

        order_id = format_order_id(options[:order_id])
        convenience_id = konbini.convenience_id

        post = {}

        post[:AccessID] = options[:AccessID]
        post[:AccessPass] = options[:AccessPass]

        add_convenience_store( post, konbini.convenience_id )
        add_customer_info( post, options[:billing_address] )
        add_order( post, order_id )
        post[:PaymentTermDay] = options[:payment_term_day] if options[:payment_term_day]

        response = commit 'pay', post

        if successful_konbini? response
          update_konbini_information(konbini, response)

          return Response.new true, 'Success', response, { test: test? }
        end

        return Response.new false, response[:errors], response, { test: test? }
      end

      private
      def action_uri( name )
        case name
        when 'prepare'
          '/payment/EntryTranCvs.idPass'
        when 'pay'
          '/payment/ExecTranCvs.idPass'
        else
          raise "GMO Konbini Action #{name} is unsupported"
        end
      end

      def add_convenience_store( post, convenience_id )
        post[:Convenience] = convenience_id
        post[:ReceiptsDisp11] = @shop_name
        post[:ReceiptsDisp12] = @shop_phone
        post[:ReceiptsDisp13] = @shop_hours
      end

      def update_konbini_information konbini, response
        konbini.confirmation = response[:ConfNo].first
        # Response time(PaymentTerm and TranDate) is tokyo time (i.e. 20130101235959). But they have not time zone.
        konbini.end_date = response[:PaymentTerm].first.to_s.concat(JST).to_datetime # hope we have activesupport
        konbini.receipt = response[:ReceiptNo].first
        konbini.transaction_date = response[:TranDate].first.to_s.concat(JST).to_datetime
        konbini.check_string = response[:CheckString].first
        konbini.save!
      end

      def add_customer_info( post, billing_address )
        post[:CustomerName] = encode_shift_jis(billing_address[:name]) # .. this this last+first
        post[:CustomerKana] = encode_shift_jis(billing_address[:kana]) # spree_kana specific
        post[:TelNo] = billing_address[:phone].gsub(/\D/,'')
      end

      def encode_shift_jis(japanese_text)
        japanese_text.encode('Shift_JIS')
      rescue Encoding::UndefinedConversionError
        itaiji_converter.convert_seijitai(japanese_text).encode('Shift_JIS',
                                                                :invalid => :replace,
                                                                :undef => :replace)
      end

      def itaiji_converter
        @converter ||= ::Itaiji::Converter.new
      end
    end
  end
end
