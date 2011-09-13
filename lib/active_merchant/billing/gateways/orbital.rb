require File.dirname(__FILE__) + '/orbital/orbital_soft_descriptors.rb'
require "rexml/document"

module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    # For more information on Orbital, visit the {integration center}[http://download.chasepaymentech.com]
    #     
    # ==== Authentication Options
    # 
    # The Orbital Gateway supports two methods of authenticating incoming requests:
    # Source IP authentication and Connection Username/Password authentication
    # 
    # In addition, these IP addresses/Connection Usernames must be affiliated with the Merchant IDs 
    # for which the client should be submitting transactions.
    # 
    # This does allow Third Party Hosting service organizations presenting on behalf of other 
    # merchants to submit transactions.  However, each time a new customer is added, the 
    # merchant or Third-Party hosting organization needs to ensure that the new Merchant IDs 
    # or Chain IDs are affiliated with the hosting companies IPs or Connection Usernames.
    # 
    # If the merchant expects to have more than one merchant account with the Orbital 
    # Gateway, it should have its IP addresses/Connection Usernames affiliated at the Chain 
    # level hierarchy within the Orbital Gateway.  Each time a new merchant ID is added, as
    # long as it is placed within the same Chain, it will simply work.  Otherwise, the additional 
    # MIDs will need to be affiliated with the merchant IPs or Connection Usernames respectively.
    # For example, we generally affiliate all Salem accounts [BIN 000001] with 
    # their Company Number [formerly called MA #] number so all MIDs or Divisions under that 
    # Company will automatically be affiliated.
    
    class OrbitalGateway < Gateway
      # AD Reset this in intialize based on default and params.
      API_VERSION = "5.2"

      DEFAULT_API_VERSION = "5.2"    # Latest is 5.2
      DEFAULT_BIN = '000002' # Tampa = 000002, Salem = 000001
      DEFAULT_COUNTRY_CODE = 'CA'
      DEFAULT_CURRENCY = 'CAD'
      DEFAULT_TERMINAL_ID = '001'
      DEFAULT_CLEAN_CC_FROM_RESPONSE = false;

      POST_HEADERS = {
        "MIME-Version" => "1.0",
        "Content-Type" => "Application/PTI#{DEFAULT_API_VERSION.gsub(/[^\d]/, '')}",
        "Content-transfer-encoding" => "text",
        "Request-number" => '1',
        "Document-type" => "Request",
        "Interface-Version" => "Ruby|ActiveMerchant|Proprietary Gateway"
      }
      
      SUCCESS, APPROVED, VALIDATED, PRENOTED, NO_REASON_TO_DECLINE, RECANDSTORED, PROVIDEDAUTH, REQREC, BINALERT, APP_PARTIAL  = '0', '00', '24', '26', '27', '28', '29', '31', '32', '34'
      APPROVAL_CODES = [APPROVED, VALIDATED, PRENOTED, NO_REASON_TO_DECLINE, RECANDSTORED, PROVIDEDAUTH, REQREC, BINALERT, APP_PARTIAL]

      AVS_RETURN_CODES = {
        '1' => 'No address supplied',
        '2' => 'Bill-to address did not pass Auth Host edit check',
        '3' => 'AVS not performed',
        '4' => 'Issuer does not participate in AVS',
        '5' => 'Edit-error - AVS data is invalid',
        '6' => 'System unavailable or time-out',
        '7' => 'Address information unavailable',
        '8' => 'Transaction Ineligible for AVS',
        '9' => 'Zip Match/Zip4 Match/Locale match',
        'A' => 'Zip Match/Zip 4 Match/Locale no match',
        'B' => 'Zip Match/Zip 4 no Match/Locale match',
        'C' => 'Zip Match/Zip 4 no Match/Locale no match',
        'D' => 'Zip No Match/Zip 4 Match/Locale match',
        'E' => 'Zip No Match/Zip 4 Match/Locale no match',
        'F' => 'Zip No Match/Zip 4 No Match/Locale match',
        'G' => 'No match at all',
        'H' => 'Zip Match/Locale match',
        'J' => 'Issuer does not participate in Global AVS',
        'JA' => 'International street address and postal match',
        'JB' => ' International street address match. Postal code not verified.',
        'JC' => 'International street address and postal code not verified.',
        'JD' => 'International postal code match. Street address not verified.',
        'M1' => 'Merchant Override Decline',
        'M2' => 'Cardholder name, billing address, and postal code matches',
        'M3' => 'Cardholder name and billing code matches',
        'M4' => 'Cardholder name and billing address match',
        'M5' => 'Cardholder name incorrect, billing address and postal code match',
        'M6' => 'Cardholder name incorrect, billing address matches',
        'M7' => 'Cardholder name incorrect, billing address matches',
        'M8' => 'Cardholder name, billing address and postal code are all incorrect',
        'N3' => 'Address matches, ZIP not verified',
        'N4' => 'Address and ZIP code not verified due to incompatible formats',
        'N5' => 'Address and ZIP code match (International only)',
        'N6' => 'Address not verified (International only)',
        'N7' => 'ZIP matches, address not verified',
        'N8' => 'Address and ZIP code match (International only)',
        'N9' => 'Address and ZIP code match (UK only)',
        'R' => 'Issuer does not participate in AVS',
        'UK' => 'Unknown',
        'X' => 'Zip Match/Zip 4 Match/Address Match',
        'Z' => 'Zip Match/Locale no match',
      }

      # These code classifications are specific to company x make this customizable
      AVS_HARD_FAIL_CODES = ['D','E','F','G','JC','M1','M8','N4','JA','JB','JD','N5','N6','N8','N9','UK'] # rejected by provider
      AVS_SOFT_FAIL_CODES = ['A','C','M4','M5','M6','M7','N3','N7','Z'] # could be an fraud issue
      AVS_SERVICE_ERROR_CODES = ['1','2','3','4','5','6','7','8','J','R']
      AVS_PASS_CODES = ['9','B','H','M2','M3','X']
      AVS_BYPASS_AD = ['A','C','N7','Z'] # bypass street address check
      AVS_HARD_UNEXPECTED_LOG = ['JA','JB','JD','N5','N6','N8','N9','UK'] # Log these unexpected errors.
      CVV_FAIL_CODES = ['N', 'P', 'I', 'Y']

      # zipcode errors
      AVS_BAD_ZIP = ['D','E','F','G','N3','N4','JB','JC']

      # These response codes should map to an invalid billing address
      AVS_BAD_ADDRESS = ['C','E','G','JC','JD','M8','N4','N6','N7','Z']
      FAILOVER_RETRIES = 3

      class_attribute :primary_test_url, :secondary_test_url, :primary_live_url, :secondary_live_url
      
      self.primary_test_url = "https://orbitalvar1.paymentech.net/authorize"
      self.secondary_test_url = "https://orbitalvar2.paymentech.net/authorize"
      
      self.primary_live_url = "https://orbital1.paymentech.net/authorize"
      self.secondary_live_url = "https://orbital2.paymentech.net/authorize"
      
      self.supported_countries = ["US", "CA"]
      self.default_currency = DEFAULT_CURRENCY
      self.supported_cardtypes = [:visa, :master, :american_express, :discover, :diners_club, :jcb]
      
      self.display_name = 'Orbital Paymentech'
      self.homepage_url = 'http://chasepaymentech.com/'
      
      self.money_format = :cents
            
      CURRENCY_CODES = { 
        "AUD" => '036',
        "CAD" => '124',
        "CZK" => '203',
        "DKK" => '208',
        "HKD" => '344',
        "ICK" => '352',
        "JPY" => '392',
        "MXN" => '484',
        "NZD" => '554',
        "NOK" => '578',
        "SGD" => '702',
        "SEK" => '752',
        "CHF" => '756',
        "GBP" => '826',
        "USD" => '840',
        "EUR" => '978'
      }

      def initialize(options = {})
        unless options[:ip_authentication] == true
          requires!(options, :login, :password, :merchant_id)
        end

        @options = options
        @logger = options[:logger] || (defined?(RAILS_DEFAULT_LOGGER) && RAILS_DEFAULT_LOGGER)
        @options[:api_version] ||= DEFAULT_API_VERSION

        ## set Content-Type header
        POST_HEADERS["Content-Type"] = "Application/PTI#{@options[:api_version].gsub(/[^\d]/, '')}"

        @options[:bin_id] ||= DEFAULT_BIN
        @options[:terminal_id] ||= DEFAULT_TERMINAL_ID
        @options[:country_code] ||= DEFAULT_COUNTRY_CODE
        @options[:currency] ||= DEFAULT_CURRENCY
        @options.has_key?(:clean_cc_from_response) || @options[:clean_cc_from_response] = DEFAULT_CLEAN_CC_FROM_RESPONSE
        
        if !@options.has_key?(:retry_safe) || @options[:retry_safe]
          self.retry_safe = true
        else
          self.retry_safe = false
        end
        
        self.class.default_currency = @options[:currency]

        super
      end
      
      # A – Authorization request
      def authorize(money, creditcard, options = {})
        order = build_new_order_xml('A', money, options) do |xml|
          add_creditcard(xml, creditcard, options[:currency])        
          add_address(xml, creditcard, options)   
        end

        #puts "authorize: #{order}"

        commit_and_filter(order)
      end
      
      # AC – Authorization and Capture
      def purchase(money, creditcard, options = {})
        order = build_new_order_xml('AC', money, options) do |xml|
          add_creditcard(xml, creditcard, options[:currency])
          add_address(xml, creditcard, options)   
        end

        commit_and_filter(order)
      end                       
      
      # MFC - Mark For Capture
      def capture(money, authorization, options = {})
        commit(build_mark_for_capture_xml(money, authorization, options))
      end
      
      # R – Refund request
      def refund(money, authorization, options = {})
        order = build_new_order_xml('R', money, options.merge(:authorization => authorization)) do |xml|
          add_refund(xml, options[:currency])
        end

        commit_and_filter(order)
      end

      def credit(money, authorization, options= {})
        deprecated CREDIT_DEPRECATION_MESSAGE
        refund(money, authorization, options)
      end
      
      # TODO add additions might be dependent on latest api version.
      # setting money to nil will perform a full void
      def void(money, authorization, options = {})
        order = build_void_request_xml(money, authorization, options) do |xml|
          add_online_reversal_ind_xml(xml, options[:online_reversal_ind]) if options[:online_reversal_ind] && @options[:api_version].to_f >= 5.2
        end
        @logger.debug("void request #{order.inspect}") if @logger
        commit(order)
      end
    
      private                       
            
      def add_customer_data(xml, options)
        if options[:customer_ref_num]
          xml.tag! :CustomerProfileFromOrderInd, 'S'
          xml.tag! :CustomerRefNum, options[:customer_ref_num]
        else
          xml.tag! :CustomerProfileFromOrderInd, 'A'
        end

        xml.tag! :CustomerProfileOrderOverrideInd, options[:customer_profile_order_override_ind] if options[:customer_profile_order_override_ind]
      end
      
      def add_soft_descriptors(xml, soft_desc)
        xml.tag! :SDMerchantName, soft_desc.merchant_name
        xml.tag! :SDProductDescription, soft_desc.product_description
        xml.tag! :SDMerchantCity, soft_desc.merchant_city
        xml.tag! :SDMerchantPhone, soft_desc.merchant_phone
        xml.tag! :SDMerchantURL, soft_desc.merchant_url
        xml.tag! :SDMerchantEmail, soft_desc.merchant_email
      end

      def add_address(xml, creditcard, options)      
        if address = options[:billing_address] || options[:address]
          xml.tag! :AVSzip, address[:zip]
          xml.tag! :AVSaddress1, address[:address1]
          xml.tag! :AVSaddress2, address[:address2]
          xml.tag! :AVScity, address[:city]
          xml.tag! :AVSstate, address[:state]
          xml.tag! :AVSphoneNum, address[:phone] ? address[:phone].scan(/\d/).join.to_s : nil
          xml.tag! :AVSname, creditcard.name
          xml.tag! :AVScountryCode, address[:country]
        end
      end

      def add_creditcard(xml, creditcard, currency=nil)
        xml.tag! :AccountNum, creditcard.number
        xml.tag! :Exp, expiry_date(creditcard)
        
        xml.tag! :CurrencyCode, currency_code(currency)
        xml.tag! :CurrencyExponent, '2' # Will need updating to support currencies such as the Yen.
        
        xml.tag! :CardSecVal,  creditcard.verification_value if creditcard.verification_value?
      end
      
      def add_refund(xml, currency=nil)
        xml.tag! :AccountNum, nil
        
        xml.tag! :CurrencyCode, currency_code(currency)
        xml.tag! :CurrencyExponent, '2' # Will need updating to support currencies such as the Yen.
      end
      
      def parse(body)
        response = {}
        xml = REXML::Document.new(body)
        root = REXML::XPath.first(xml, "//Response") ||
               REXML::XPath.first(xml, "//ErrorResponse")
        if root
          root.elements.to_a.each do |node|
            recurring_parse_element(response, node)
          end
        end
        response
      end     
      
      def recurring_parse_element(response, node)
        if node.has_elements?
          node.elements.each{|e| recurring_parse_element(response, e) }
        else
          response[node.name.underscore.to_sym] = node.text
        end
      end
      
      def commit(order)
        headers = POST_HEADERS.merge("Content-length" => order.size.to_s)
        request = lambda {return parse(ssl_post(remote_url, order, headers))}
        
        # Failover URL will be used in the event of a connection error
        begin response = request.call; rescue ConnectionError; retry end
        
        Response.new(success?(response), message_from(response), response,
          {:authorization => "#{response[:tx_ref_num]};#{response[:order_id]}",
           :test => self.test?,
           :avs_result => {:code => response[:avs_resp_code]},
           :cvv_result => response[:cvv2_resp_code]
          }
        )
      end
      
      def remote_url
        unless $!.class == ActiveMerchant::ConnectionError
          self.test? ? self.primary_test_url : self.primary_live_url
        else
          self.test? ? self.secondary_test_url : self.secondary_live_url
        end
      end

      def success?(response)
        if response[:message_type] == "R"
          response[:proc_status] == SUCCESS
        else
          response[:proc_status] == SUCCESS &&
          response[:resp_code] == APPROVED 
        end
      end
      
      def message_from(response)
        success?(response) ? 'APPROVED' : response[:resp_msg] || response[:status_msg]
      end
      
      def ip_authentication?
        @options[:ip_authentication] == true
      end

      def build_new_order_xml(action, money, parameters = {})
        requires!(parameters, :order_id)
        xml = Builder::XmlMarkup.new(:indent => 2)
        xml.instruct!(:xml, :version => '1.0', :encoding => 'UTF-8')
        xml.tag! :Request do
          xml.tag! :NewOrder do
            xml.tag! :OrbitalConnectionUsername, @options[:login] unless ip_authentication?
            xml.tag! :OrbitalConnectionPassword, @options[:password] unless ip_authentication?
            xml.tag! :IndustryType, "EC" # E-Commerce transaction 
            xml.tag! :MessageType, action
            xml.tag! :BIN, @options[:bin_id]
            xml.tag! :MerchantID, @options[:merchant_id]
            xml.tag! :TerminalID, parameters[:terminal_id] || @options[:terminal_id]
            
            yield xml if block_given?
            
            xml.tag! :Comments, parameters[:comments] if parameters[:comments]
            xml.tag! :OrderID, parameters[:order_id].to_s[0...22]
            xml.tag! :Amount, amount(money)
            
            # Append Transaction Reference Number at the end for Refund transactions
            if action == "R"
              tx_ref_num, _ = parameters[:authorization].split(';')
              xml.tag! :TxRefNum, tx_ref_num
            end
          end
        end
        xml.target!
      end
      
      def build_mark_for_capture_xml(money, authorization, parameters = {})
        tx_ref_num, order_id = authorization.split(';')
        xml = Builder::XmlMarkup.new(:indent => 2)
        xml.instruct!(:xml, :version => '1.0', :encoding => 'UTF-8')
        xml.tag! :Request do
          xml.tag! :MarkForCapture do
            xml.tag! :OrbitalConnectionUsername, @options[:login] unless ip_authentication?
            xml.tag! :OrbitalConnectionPassword, @options[:password] unless ip_authentication?
            xml.tag! :OrderID, order_id
            xml.tag! :Amount, amount(money)
            xml.tag! :BIN, @options[:bin_id]
            xml.tag! :MerchantID, @options[:merchant_id]
            xml.tag! :TerminalID, parameters[:terminal_id] || @options[:terminal_id]
            xml.tag! :TxRefNum, tx_ref_num
          end
        end
        xml.target!
      end
      
      def build_void_request_xml(money, authorization, parameters = {})
        requires!(parameters, :transaction_index)
        tx_ref_num, order_id = authorization.split(';')
        xml = Builder::XmlMarkup.new(:indent => 2)
        xml.instruct!(:xml, :version => '1.0', :encoding => 'UTF-8')
        xml.tag! :Request do
          xml.tag! :Reversal do
            xml.tag! :OrbitalConnectionUsername, @options[:login] unless ip_authentication?
            xml.tag! :OrbitalConnectionPassword, @options[:password] unless ip_authentication?
            xml.tag! :TxRefNum, tx_ref_num
            xml.tag! :TxRefIdx, parameters[:transaction_index]
            xml.tag! :AdjustedAmt, amount(money)
            xml.tag! :OrderID, order_id
            xml.tag! :BIN, @options[:bin_id]
            xml.tag! :MerchantID, @options[:merchant_id]
            xml.tag! :TerminalID, parameters[:terminal_id] || @options[:terminal_id]
            yield xml if block_given?
          end
        end
        xml.target!
      end

      def add_online_reversal_ind_xml(xml, online_reversal_ind)
        xml.tag! :OnlineReversalInd, online_reversal_ind
      end
      
      def currency_code(currency)
        CURRENCY_CODES[(currency || self.default_currency)].to_s
      end
      
      def expiry_date(credit_card)
        "#{format(credit_card.month, :two_digits)}#{format(credit_card.year, :two_digits)}"
      end

      # This method replaces a commit() with an optional method to clean cc cvv values from orbital response objects.
      # Useful for those users who dont need this data and dont want to risk pci compliance issues related to logging or storing cc/cvv numbers inadvertantly.
      def commit_and_filter(order)
        response = commit(order)

        remove_cc_from_response_hash(response) if @options[:clean_cc_from_response]

        response
      end

      def remove_cc_from_response_hash(response)
        if response.params.is_a?(Hash)
          ['account_num', :account_num, 'cc_account_num', :cc_account_num].each { |key| response.params.delete(key) if response.params.has_key?(key) }
        end
      end
    end
  end
end
