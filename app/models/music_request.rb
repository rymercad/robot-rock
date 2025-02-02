class MusicRequest < ApplicationRecord
  belongs_to :user

  validates :prompt, presence: true
  validate :no_duplicate_active_prompt, if: :active?

  default_scope { order(active: :desc, updated_at: :desc) }

  before_save :ensure_only_one_active

  scope :active, -> { where(active: true) }

  private

  # Validates that there are no duplicate active prompts for the same user.
  def no_duplicate_active_prompt
    return unless user.music_requests.active.where(prompt: prompt).exists?

    errors.add(:prompt, 'already exists.')
  end

  # Ensures that only one music request is active at a time for the user.
  def ensure_only_one_active
    if active
      user.music_requests.update_all(active: false)
    end
  end
end
