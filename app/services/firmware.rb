# Device firmware releases (over the air and over USB).
#
# A release is a FirmwareBundle: one tested set of signed images (FirmwareImage, one per
# component) for one hardware revision, on a channel, with a staged rollout. Clients ask
# Firmware::Offer (GET /api/v1/firmware/check) what to install and send install results back
# (FirmwareReport, POST /api/v1/firmware/reports). CI uploads drafts (POST
# /api/v1/admin/firmware/bundles, token auth); publishing is an admin action. See the
# "Device firmware" section of the README.
module Firmware
  # Install order on the device: radio net core, radio app core, then the main MCU's assets and
  # firmware (those two as one bootloader transaction).
  COMPONENTS = %w[nrf_net nrf_app stm32_assets stm32].freeze

  # Components that must ship and install together: the firmware checks at boot that the assets
  # image is the one it was built with, so neither is offered without the other. Empty this once
  # that stamp is a content hash and a firmware-only change keeps it.
  PAIRED_COMPONENTS = %w[stm32 stm32_assets].freeze

  # Upper bounds per image, the size of the slot each one is staged in.
  MAX_IMAGE_BYTES = {
    'nrf_net' => 1.megabyte,
    'nrf_app' => 1.megabyte,
    'stm32_assets' => 16.megabytes,
    'stm32' => 1.megabyte
  }.freeze

  CHANNELS = %w[internal beta stable].freeze

  # Which bundle channels a client on a channel sees: beta also gets stable, internal gets all.
  CHANNEL_AUDIENCE = {
    'stable' => %w[stable],
    'beta' => %w[beta stable],
    'internal' => %w[internal beta stable]
  }.freeze

  # SHA-256 of the device's unique ID (salted on the device), lowercase hex. The raw ID never
  # reaches the server.
  DEVICE_HASH_FORMAT = /\A[0-9a-f]{64}\z/.freeze
  HW_REV_FORMAT = /\A[A-Za-z0-9_.-]{1,32}\z/.freeze

  def self.config
    @config ||= Settings.new
  end

  # Tests use this to drop overrides.
  def self.reset_config!
    @config = nil
  end
end
