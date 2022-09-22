# frozen_string_literal: true

class TransactionsController < ApplicationController
  skip_before_action :verify_authenticity_token, only: %i[create paid]
  before_action :authenticate_user!, except: %i[paid]
  include ProjectPriceSum

  def index
    @transactions = Transaction.order(created_at: :desc)

  end

  def create
    if Transaction.can_buy?(params['projectId'], params['donateItemTitle'], params['amount'])
      @transaction = Transaction.new(user_id: current_user.id,
                                    project_id: params['projectId'],
                                    donate_item_id:,
                                    price:,
                                    amount: params['amount'])
      create_order_and_ecpay(params['projectId'])
    else
      render :amount_error
    end
  end

  def paid
    find_transaction_by_serial_after_ecpay
    pending_to_paid
    decrease_donate_amount(DonateItem.find(@serial_transaction.donate_item_id).title, @serial_transaction.amount)
    increase_donate_count
    sign_in(User.find(@serial_transaction.user_id))
    render :paid
  end

  def destroy
    @transaction = Transaction.find_by!(id: params[:id])
    @transaction.update(deleted_at: Time.now)
    redirect_to transactions_path, notice: '此筆交易已刪除...'
  end

  private

  def donate_item_id
    current_project = Project.find(params['projectId'])
    current_donate_item = DonateItem.find_by!(project_id: current_project, title: params['donateItemTitle']).id
  end

  def price
    params['additionalSum'].to_i
  end

  def produce_ecpay_basic_params
    @merchant_trade_no = @transaction.serial
    @merchant_trade_date = Time.now.strftime('%Y/%m/%d %H:%M:%S')
    @item_name = params['donateItemTitle']
    @total_amount = price
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

  def followers_not_recepted_yet(project_id)
    @followers = Follow.where(followable_id: project_id, followable_type: 'Project', mail_sent: 'false')
  end

  def notify_achievement_to_followers(project_id)
    if percentage_of_currency(project_id) >= 100 && followers_not_recepted_yet(project_id).present? === true
      @followers.each do |follower|
        MailWorkerJob.perform_later(follower, Project.find(follower.followable_id).title)
        follower.update(:mail_sent => 'true')
      end
    end
  end
  
  def find_transaction_by_serial_after_ecpay
    @serial_transaction = Transaction.find_by!(serial: params[:MerchantTradeNo])
  end

  def find_project
    @project = Project.find(find_transaction_by_serial_after_ecpay.project_id)
  end

  def payment_write_into_database
    find_project
    total = project_current_total(@project.id) + @serial_transaction.price
    @project.update(current_total: total)
  end

  def pending_to_paid
    payment_write_into_database
    notify_achievement_to_followers(@project.id)
    @serial_transaction.pay!
  end

  def increase_donate_count
    current_donate_item = DonateItem.find(@serial_transaction.donate_item_id)
    current_donate_item.increment(:donate_logs_count).save
  end

  def decrease_donate_amount(donate_item_title, amount)
    donate_item = DonateItem.find_by!(title: donate_item_title)
    donate_item.with_lock do
      donate_item.decrement(:amount, amount.to_i)
      donate_item.save
    end
  end
end