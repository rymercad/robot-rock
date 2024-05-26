class MusicRequestsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_request, only: [:activate, :destroy]

  def index
    @todays_playlists = current_user&.todays_playlists
    @music_requests = current_user.music_requests
  end

  def activate
    current_user.music_requests.update_all(active: false)
    @music_request.update(active: true)
    GenerateUserPlaylistsJob.perform_inline(current_user.id) if current_user.can_regenerate_playlists?
    redirect_to music_requests_path, notice: 'Your music request has been restored!'
  end

  def create
    @music_request = current_user.music_requests.build(music_request_params)
    @music_request.active = true

    if @music_request.save
      GenerateUserPlaylistsJob.perform_inline(current_user.id) if current_user.can_regenerate_playlists?
      redirect_to root_path, notice: 'Your music request has been saved!'
    else
      redirect_to root_path
    end
  end

  def destroy
    @music_request.destroy
    if @music_request.active?
      most_recent_request = current_user.music_requests.order(created_at: :desc).first
      most_recent_request.update(active: true) if most_recent_request.present?
      GenerateUserPlaylistsJob.perform_inline(current_user.id) if current_user.can_regenerate_playlists?
    end
    redirect_to music_requests_path, notice: 'Your music request has been deleted!'
  end

  private

  def music_request_params
    params.require(:music_request).permit(:prompt)
  end

  def set_request
    @music_request = current_user.music_requests.find(params[:id])
  end
end
