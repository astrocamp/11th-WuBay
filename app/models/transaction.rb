# frozen_string_literal: true

class Transaction < ApplicationRecord
  include PriceSumable

  acts_as_paranoid
  default_scope { where(deleted_at: nil) }

  # relationship
  belongs_to :user
  belongs_to :donate_item

  before_create :create_serial
  after_commit :decrease_donate_amount, on: :create

  def create_serial
    self.serial = SecureRandom.alphanumeric(6)
  end

  def self.can_buy?(project_id, donate_item_title, amount)
    donate_item = DonateItem.find_by!(project_id: project_id, title: donate_item_title)
    true if donate_item.amount === nil || donate_item.amount > 0 && amount.to_i <= donate_item.amount
  end

  # transaction state
  include AASM

  aasm column: 'state', no_direct_assignment: true do
    state :pending, initial: true
    state :paid, :failed, :cancellation, :refunded

    event :pay, after: :notify_achievement_to_followers do
      transitions from: %i[pending failed], to: :paid
    end

    event :refund do
      transitions from: :paid, to: :refunded
    end

    event :fail do
      transitions from: :pending, to: :failed
    end

    event :cancel do
      transitions from: %i[pending failed], to: :cancellation
    end
  end

  private

  def decrease_donate_amount
    donate_item = DonateItem.find_by!(title: self.donate_item.title)
    if donate_item.amount != nil
      donate_item.with_lock do
        donate_item.decrement(:amount, self.amount)
        donate_item.save
      end
    end
  end

  def followers_not_recepted_yet
    @followers = Follow.where(followable_id: self.project_id, followable_type: 'Project', mail_sent: 'false')
  end

  def notify_achievement_to_followers
    return unless mail_job_work?

    @followers.each do |follower|
      MailWorkerJob.perform_later(follower, Project.find(follower.followable_id).title)
      follower.update(:mail_sent => 'true')
    end
  end

  def mail_job_work?
    percentage_of_currency(self.project_id) >= 100 && followers_not_recepted_yet.present? == true
  end
end
