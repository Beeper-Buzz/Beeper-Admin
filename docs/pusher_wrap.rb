require 'pusher'

channels_client =
    Pusher::Client.new(
        app_id: 'dna-api-id',
        key: 'dna-api-key',
        secret: 'dna-api-secret',
        cluster: 'dna-api-cluster',
        use_tls: true
    )

:cluster
