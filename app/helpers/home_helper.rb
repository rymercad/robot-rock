module HomeHelper
  def lock_button_confirmation_message(playlist)
    automatically_clean_up_old_playlists = current_user.preference&.automatically_clean_up_old_playlists
    if automatically_clean_up_old_playlists
      if playlist.locked?
        "Unlocking the playlist will allow it to be regenerated and be automatically deleted tomorrow. Are you sure you want to unlock it?"
      else
        "Locking the playlist will prevent it from being regenerated or being automatically deleted tomorrow. Are you sure you want to lock it?"
      end
    else
      if playlist.locked?
        "Unlocking the playlist will allow it to be regenerated again. Are you sure you want to unlock it?"
      else
        "Locking the playlist will prevent it from being regenerated. Are you sure you want to lock it?"
      end
    end
  end

  def generate_playlists_button_class
    css_class = ["button is-fullwidth"]
    css_class << "is-loading" if @todays_playlists.present? && @todays_playlists.any?(&:processing)
    css_class.join(" ")
  end
end
