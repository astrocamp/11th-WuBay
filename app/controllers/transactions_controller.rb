# frozen_string_literal: true

class TransactionsController < ApplicationController
  include PriceSumable

  skip_before_action :verify_authenticity_token, only: %i[create paid]
  before_action :authenticate_user!, except: %i[paid]
  before_action :check_amount_enough, only: %i[create]

  def index
    @transactions = Transaction.order(created_at: :desc)
  end

  def create
    @transaction = Transaction.new(
      user_id: current_user.id,
      project_id: params['projectId'],    
      donate_item_id:,
      price: params['additionalSum'].to_i,
      amount: params['amount'],
    )

    create_order_and_ecpay(params['projectId'])
  end

  def paid
    if params['RtnMsg'] === "Succeeded"
      find_transaction_by_serial_after_ecpay
      pending_to_paid
      increase_donate_count
      sign_in(User.find(@serial_transaction.user_id))
      return '1|OK'
    else
      @serial_transaction.fail!
      render :transaction_error
    end
  end

  def destroy
    @transaction = Transaction.find_by!(id: params[:id])
    @transaction.update(deleted_at: Time.now)
    @transaction.cancel!
    redirect_to transactions_path, notice: '此筆交易已刪除...'
  end

  private

  def check_amount_enough
    render :amount_error unless Transaction.can_buy?(params['projectId'], params['donateItemTitle'], params['amount'])
    return
  end

  def donate_item_id
    current_project = Project.find(params['projectId'])
    current_donate_item = DonateItem.find_by!(project_id: current_project, title: params['donateItemTitle']).id
  end

  def produce_ecpay_basic_params
    @merchant_trade_no = @transaction.serial
    @merchant_trade_date = Time.now.strftime('%Y/%m/%d %H:%M:%S')
    @item_name = params['donateItemTitle']
    @total_amount = params['additionalSum'].to_i
  end

  def order_params_for_ecpay_params
    { 
      merchant_trade_date: @merchant_trade_date,
      merchant_trade_no: @merchant_trade_no,
      item_name: @item_name,
      total_amount: @total_amount
    }
  end

  def create_order_and_ecpay(project_id)
    if @transaction.save
      produce_ecpay_basic_params
      @ecpay_params = Payment::EcpayRequest.new(order_params_for_ecpay_params).perform
    else
      render :save_error
    end
  end
  
  def find_transaction_by_serial_after_ecpay
    @serial_transaction = Transaction.find_by!(serial: params[:MerchantTradeNo])
  end

  def pending_to_paid
    @project = Project.find(find_transaction_by_serial_after_ecpay.project_id)
    total = project_current_total(@project.id) + @serial_transaction.price
    @project.update(current_total: total)
    @serial_transaction.pay!
  end

  def increase_donate_count
    current_donate_item = DonateItem.find(@serial_transaction.donate_item_id)
    current_donate_item.donate_logs.create(ip_address: request.remote_ip)
  end
end
