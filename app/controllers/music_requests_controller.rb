class MusicRequestsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_request, only: [:activate, :destroy]

  def index
    @todays_playlists = current_user.todays_playlists
    @music_requests = current_user.music_requests
  end

  def activate
    current_user.music_requests.update_all(active: false)
    @music_request.update(active: true)
    if current_user.can_regenerate_playlists?
      GenerateUserPlaylistsJob.perform_inline(current_user.id) 
      current_user.todays_playlists.each(&:processing!)
    end
    redirect_to music_requests_path, notice: 'Your music request has been restored!'
  end

  def create
    @music_request = current_user.music_requests.build(music_request_params)
    @music_request.active = true
    @music_request.save
    if @music_request.prompt.present? && current_user.can_regenerate_playlists?
      GenerateUserPlaylistsJob.perform_inline(current_user.id) 
      current_user.todays_playlists.each(&:processing!)
      redirect_to root_path, notice: 'Your playlists are being generated ✨'
    elsif !current_user.can_regenerate_playlists?
      redirect_to root_path, alert: 'Your playlists can’t be generated at this time.'
    elsif @music_request.prompt.blank?
      redirect_to root_path, alert: 'Your playlists can’t be generated if you leave your request blank!'
    end
  end

  def destroy
    if current_user.music_requests.count > 1
      @music_request.destroy
      if @music_request.active?
        most_recent_request = current_user.music_requests.order(created_at: :desc).first
        most_recent_request.update(active: true) if most_recent_request.present?
        if current_user.can_regenerate_playlists?
          GenerateUserPlaylistsJob.perform_inline(current_user.id) 
          current_user.todays_playlists.each(&:processing!)
        end
      end
      redirect_to music_requests_path, notice: 'Your music request has been deleted!'
    else
      redirect_to music_requests_path, alert: 'You can’t delete your only music request!'
    end
  end

  private

  def music_request_params
    params.require(:music_request).permit(:prompt)
  end

  def set_request
    @music_request = current_user.music_requests.find(params[:id])
  end
end
