require 'test_helper'

class KomojuTest < Test::Unit::TestCase
  def setup
    @gateway = KomojuGateway.new(:login => 'login')

    @credit_card = credit_card
    @konbini = {
      :type  => 'konbini',
      :store => 'lawson',
      :email => 'test@example.com',
      :phone => '09011112222'
    }
    @amount = 100

    @options = {
      :order_id => '1',
      :description => 'Store Purchase',
      :tax => "10",
      :ip => "192.168.0.1",
      :email => "valid@email.com",
      :browser_language => "en",
      :browser_user_agent => "user_agent"
    }
  end

  def test_successful_credit_card_purchase
    successful_response = successful_credit_card_purchase_response
    @gateway.expects(:ssl_post).with { |url, data|
      json = JSON.parse(data)
      assert_equal 'credit_card',                  json['payment_details']['type']
      assert_equal credit_card.number,             json['payment_details']['number']
      assert_equal credit_card.month,              json['payment_details']['month']
      assert_equal credit_card.year,               json['payment_details']['year']
      assert_equal credit_card.verification_value, json['payment_details']['verification_value']
      assert_equal credit_card.first_name,         json['payment_details']['given_name']
      assert_equal credit_card.last_name,          json['payment_details']['family_name']
      assert_equal @options[:email],               json['fraud_details']['customer_email']
      assert_equal @options[:browser_language],    json['fraud_details']['browser_language']
      assert_equal @options[:browser_user_agent],  json['fraud_details']['browser_user_agent']
      assert_equal @options[:ip],                  json['fraud_details']['customer_ip']
    }.returns(JSON.generate(successful_response))

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response

    assert_equal successful_response["id"], response.authorization
    assert response.test?
  end

  def test_successful_konbini_purchase
    successful_response = successful_konbini_purchase_response
    @gateway.expects(:ssl_post).with { |url, data|
      json = JSON.parse(data)
      assert_equal 'konbini'    ,    json['payment_details']['type']
      assert_equal @options[:email], json['payment_details']['email']
    }.returns(JSON.generate(successful_response))

    response = @gateway.purchase(@amount, @konbini, @options)
    assert_success response

    assert_equal successful_response["id"], response.authorization
    assert response.test?
  end

  def test_successful_konbini_capture
    response = @gateway.capture(@amount, @konbini, @options)
    assert_success response

    assert_equal response.message, "Success"
    assert response.test?
  end

  def test_failed_purchase
    raw_response = mock
    raw_response.expects(:code)
    raw_response.expects(:body).returns(JSON.generate(failed_purchase_response))
    exception = ActiveMerchant::ResponseError.new(raw_response)

    @gateway.expects(:ssl_post).raises(exception)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
    assert_equal "missing_parameter", response.error_code
    assert response.test?
  end

  def test_timeout_failure
    raw_response = mock
    raw_response.expects(:code).returns(504)
    exception = ActiveMerchant::ResponseError.new(raw_response)

    @gateway.expects(:ssl_post).raises(exception)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
    assert_equal "gateway_timeout", response.error_code
  end

  def test_successful_credit_card_refund
    total = 108
    refund_message = "Full Refund"
    successful_response = successful_credit_card_refund_response
    @gateway.expects(:ssl_post).returns(JSON.generate(successful_response))

    @options.update(:refund_message => refund_message)
    response = @gateway.refund(total,  "7e8c55a54256ce23e387f2838c", @options)
    assert_success response

    assert_equal successful_response["id"], response.authorization
    assert_equal total, response.params["amount_refunded"]
    assert_equal total, response.params["refunds"][0]["amount"]
    assert_equal refund_message, response.params["refunds"][0]["description"]
    assert response.test?
  end

  def test_successful_credit_card_void
    total = 108
    successful_response = successful_credit_card_refund_response
    @gateway.expects(:ssl_post).returns(JSON.generate(successful_response))

    response = @gateway.void("7e8c55a54256ce23e387f2838c", {})
    assert_success response

    assert_equal successful_response["id"], response.authorization
    assert_equal total, response.params["amount_refunded"]
    assert_equal total, response.params["refunds"][0]["amount"]
    assert response.test?
  end

  def test_successful_credit_card_store
    successful_response = successful_credit_card_store_response
    @gateway.expects(:ssl_post).returns(JSON.generate(successful_response))

    response = @gateway.store(@credit_card, @options)
    assert_success response

    assert_equal successful_response["id"], response.authorization
    assert response.test?
  end

  private

  def successful_credit_card_purchase_response
    {
      "id" => "7e8c55a54256ce23e387f2838c",
      "resource" => "payment",
      "status" => "captured",
      "amount" => 100,
      "tax" => 8,
      "payment_deadline" => nil,
      "payment_details" => {
        "type" => "credit_card",
        "brand" => "visa",
        "last_four_digits" => "2220",
        "month" => 9,
        "year" => 2016
      },
      "payment_method_fee" => 0,
      "total" => 108,
      "currency" => "JPY",
      "description" => "Store Purchase",
      "subscription" => nil,
      "succeeded" => true,
      "captured_at" => "2015-03-20T04:51:48Z",
      "metadata" => {
        "order_id" => "262f2a92-542c-4b4e-a68b-5b6d54a438a8"
      },
      "created_at" => "2015-03-20T04:51:48Z"
    }
  end

  def successful_credit_card_refund_response
    {
      "id" => "7e8c55a54256ce23e387f2838c",
      "resource" => "payment",
      "status" => "refunded",
      "amount" => 100,
      "tax" => 8,
      "payment_deadline" => nil,
      "payment_details" => {
        "type" => "credit_card",
        "brand" => "visa",
        "last_four_digits" => "2220",
        "month" => 9,
        "year" => 2016
      },
      "payment_method_fee" => 0,
      "total" => 108,
      "currency" => "JPY",
      "description" => "Store Purchase",
      "subscription" => nil,
      "captured_at" => nil,
      "metadata" => {
        "order_id" => "262f2a92-542c-4b4e-a68b-5b6d54a438a8"
      },
      "created_at" => "2015-03-20T04:51:48Z",
      "amount_refunded" => 108,
      "refunds" =>
        [{"id" => "bdd5d67a0a5a67dc2779bc7726119ece",
        "resource" => "refund",
        "amount" => 108,
        "currency" => "JPY",
        "payment" => "9eb7efedb13cedd7963dfa3b78",
        "description" => "Full Refund",
        }]
    }
  end

  def successful_credit_card_store_response
    {
      "id" => "tok_71864f005c9799cc4259b0e3fe3082f9fdba0163115ed77743ee22e070d2cf65chy4ap7vkdlkqymh73afwr652",
   "resource" => "token",
   "created_at" => "2016-04-26T03:04:07Z",
   "payment_details" =>
      {"type"=>"credit_card",
       "given_name" => "taro",
       "family_name" => "yamada"
      }
    }
  end


  def failed_purchase_response
    {
      "error" => {
        "code" => "missing_parameter",
        "message" => "A required parameter (currency) is missing",
        "param" => "currency"
      }
    }
  end

  def successful_konbini_purchase_response
    {
      "id" => "98f5d7883c951bc21c1dfe947b",
      "resource" => "payment",
      "status" => "authorized",
      "amount" => 1000,
      "tax" => 80,
      "payment_deadline" => "2015-03-21T14:59:59Z",
      "payment_details" => {
        "type" => "konbini",
        "store" => "lawson",
        "confirmation_code" => "3769",
        "receipt" => "WNT30356930",
        "instructions_url" => "http://www.degica.com/cvs/lawson"
      },
     "payment_method_fee" => 150,
     "total" => 1230,
     "currency" => "JPY",
     "description" => nil,
     "subscription" => nil,
     "succeeded" => false,
     "captured_at" => nil,
     "metadata" => {
       "order_id" => "262f2a92-542c-4b4e-a68b-5b6d54a438a8"
     },
     "created_at" => "2015-03-20T05:45:55Z"
    }
  end
end
