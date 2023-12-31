# frozen_string_literal: true

class ProjectsController < ApplicationController
  include PriceSumable

  before_action :authenticate_user!, except: %i[index show]
  before_action :find_project, only: %i[show edit destroy update follow]

  def index
    @projects = Project.all
    respond_to do |format|
      format.html { render :index }
      format.json { render json: @projects }
    end
  end

  def new
    @project = Project.new
  end

  def edit; end

  def destroy
    if @project.really_destroy!
      redirect_to '/projects', notice: '提案刪除成功 !!'
    else
      redirect_to '/projects', notice: '不能刪除 !!'
    end
  end

  def show
    @comment = Comment.new
    @comments = @project.comments.order(id: :desc)

    @donate_items = @project.donate_items.order(created_at: :asc)

    @donate_users_count = Transaction.where(project_id: @project.id).select(:user_id).map(&:user_id).uniq.count

    @follow_state = follow_list.empty? ? '追蹤專案' : '取消追蹤'

    project_current_total(params[:id])
    percentage_of_currency(params[:id])
  end

  def update
    if @project.update(project_params)
      redirect_to project_path, notice: ' 提案更新成功 !!'
    else
      render :edit
    end
  end

  def create
    @project = current_user.projects.new(project_params)
    if @project.save
      redirect_to new_project_donate_item_path(@project.id), notice: ' 提案成功 !!'
    else
      render :new
    end
  end

  def follow
    follow_list.empty? ? add_follow : cancel_follow
  end

  private

  def project_params
    params.require(:project).permit(
      :organizer, 
      :email, 
      :phone, 
      :title, 
      :amount_target, 
      :end_time, 
      :description,
      :avatar,
    )
  end

  def find_project
    @project = Project.find(params[:id])
  end

  def follow_list
    Follow.current_user_follow_this_project(current_user&.id, params)
  end

  def add_follow
    @project.follows.create(:user_id => current_user.id, :mail_sent => "false")
    render json: { status: "been_followed" }
  end

  def cancel_follow
    follow_list.first.destroy
    render json: { status: 'cancel_follow' }
  end
end