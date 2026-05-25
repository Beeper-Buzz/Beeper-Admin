class AppSetting < ApplicationRecord
  validates :version, presence: true, format: { with: /\A\d+\.\d+\.\d+\z/, message: 'must be semantic (e.g. 1.2.3)' }

  def self.latest
    order(:updated_at).last || new(name: 'com.beeper.Buzz', platform: 'ios-android', version: '0.0.0')
  end
end
