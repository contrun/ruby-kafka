# frozen_string_literal: true

describe "Transactional producer", functional: true do
  example 'Typical transactional production' do
    producer = kafka.producer(
      transactional: true,
      transactional_id: SecureRandom.uuid
    )

    topic = create_random_topic(num_partitions: 3)

    producer.init_transactions
    producer.begin_transaction
    producer.produce('Test 1', topic: topic, partition: 0)
    producer.produce('Test 2', topic: topic, partition: 1)
    producer.deliver_messages
    producer.produce('Test 3', topic: topic, partition: 0)
    producer.produce('Test 4', topic: topic, partition: 1)
    producer.produce('Test 5', topic: topic, partition: 2)
    producer.deliver_messages
    producer.commit_transaction

    records = kafka.fetch_messages(topic: topic, partition: 0, offset: :earliest)
    expect(records.length).to eql(2)
    expect(records[0].value).to eql('Test 1')
    expect(records[1].value).to eql('Test 3')

    records = kafka.fetch_messages(topic: topic, partition: 1, offset: :earliest)
    expect(records.length).to eql(2)
    expect(records[0].value).to eql('Test 2')
    expect(records[1].value).to eql('Test 4')

    records = kafka.fetch_messages(topic: topic, partition: 2, offset: :earliest)
    expect(records.length).to eql(1)
    expect(records[0].value).to eql('Test 5')

    producer.shutdown
  end

  example 'Multiple transactional production' do
    producer = kafka.producer(
      transactional: true,
      transactional_id: SecureRandom.uuid
    )

    topic = create_random_topic(num_partitions: 3)

    producer.init_transactions
    producer.begin_transaction
    producer.produce('Test 1', topic: topic, partition: 0)
    producer.produce('Test 2', topic: topic, partition: 1)
    producer.deliver_messages
    producer.commit_transaction

    sleep 1

    producer.begin_transaction
    producer.produce('Test 3', topic: topic, partition: 0)
    producer.produce('Test 4', topic: topic, partition: 1)
    producer.produce('Test 5', topic: topic, partition: 2)
    producer.deliver_messages
    producer.commit_transaction

    records = kafka.fetch_messages(topic: topic, partition: 0, offset: :earliest)
    expect(records.length).to eql(2)
    expect(records[0].value).to eql('Test 1')
    expect(records[1].value).to eql('Test 3')

    records = kafka.fetch_messages(topic: topic, partition: 1, offset: :earliest)
    expect(records.length).to eql(2)
    expect(records[0].value).to eql('Test 2')
    expect(records[1].value).to eql('Test 4')

    records = kafka.fetch_messages(topic: topic, partition: 2, offset: :earliest)
    expect(records.length).to eql(1)
    expect(records[0].value).to eql('Test 5')
    producer.shutdown
  end

  example 'Consumer could not read not-completed transactional production' do
    producer = kafka.producer(
      transactional: true,
      transactional_id: SecureRandom.uuid
    )

    topic = create_random_topic(num_partitions: 3)

    producer.init_transactions
    producer.begin_transaction
    producer.produce('Test 1', topic: topic, partition: 0)
    producer.produce('Test 2', topic: topic, partition: 1)
    producer.produce('Test 3', topic: topic, partition: 2)
    producer.deliver_messages

    records = kafka.fetch_messages(topic: topic, partition: 0, offset: :earliest, max_wait_time: 1)
    expect(records.length).to eql(0)

    records = kafka.fetch_messages(topic: topic, partition: 1, offset: :earliest, max_wait_time: 1)
    expect(records.length).to eql(0)

    records = kafka.fetch_messages(topic: topic, partition: 2, offset: :earliest, max_wait_time: 1)
    expect(records.length).to eql(0)

    producer.commit_transaction

    records = kafka.fetch_messages(topic: topic, partition: 0, offset: :earliest, max_wait_time: 1)
    expect(records.length).to eql(1)
    expect(records[0].value).to eql('Test 1')

    records = kafka.fetch_messages(topic: topic, partition: 1, offset: :earliest, max_wait_time: 1)
    expect(records.length).to eql(1)
    expect(records[0].value).to eql('Test 2')

    records = kafka.fetch_messages(topic: topic, partition: 2, offset: :earliest, max_wait_time: 1)
    expect(records.length).to eql(1)
    expect(records[0].value).to eql('Test 3')

    producer.shutdown
  end

  example 'Consumer could not read aborted transactional production' do
    producer = kafka.producer(
      transactional: true,
      transactional_id: SecureRandom.uuid
    )

    topic = create_random_topic(num_partitions: 3)

    producer.init_transactions
    producer.begin_transaction
    producer.produce('Test 1', topic: topic, partition: 0)
    producer.produce('Test 2', topic: topic, partition: 1)
    producer.produce('Test 3', topic: topic, partition: 2)
    producer.deliver_messages
    producer.abort_transaction

    records = kafka.fetch_messages(topic: topic, partition: 0, offset: :earliest, max_wait_time: 1)
    expect(records.length).to eql(0)

    records = kafka.fetch_messages(topic: topic, partition: 1, offset: :earliest, max_wait_time: 1)
    expect(records.length).to eql(0)

    records = kafka.fetch_messages(topic: topic, partition: 2, offset: :earliest, max_wait_time: 1)
    expect(records.length).to eql(0)

    producer.shutdown
  end

  example 'Fenced-out producer' do
    transactional_id = SecureRandom.uuid
    topic = create_random_topic(num_partitions: 3)

    producer_1 = kafka.producer(
      transactional: true,
      transactional_id: transactional_id
    )

    producer_1.init_transactions
    producer_1.begin_transaction
    producer_1.produce('Test 1', topic: topic, partition: 0)
    producer_1.produce('Test 2', topic: topic, partition: 1)
    producer_1.produce('Test 3', topic: topic, partition: 2)
    producer_1.deliver_messages
    producer_1.commit_transaction

    producer_2 = kafka.producer(
      transactional: true,
      transactional_id: transactional_id
    )
    producer_2.init_transactions
    producer_2.begin_transaction
    producer_2.produce('Test 4', topic: topic, partition: 0)
    producer_2.produce('Test 5', topic: topic, partition: 1)
    producer_2.deliver_messages
    producer_2.commit_transaction

    producer_1.begin_transaction
    producer_1.produce('Test 6', topic: topic, partition: 0)
    expect do
      producer_1.deliver_messages
    end.to raise_error(Kafka::InvalidProducerEpochError)

    producer_1.shutdown
    producer_2.shutdown
  end

  example 'Concurrent transaction' do
    transactional_id = SecureRandom.uuid
    topic = create_random_topic(num_partitions: 3)

    producer_1 = kafka.producer(
      transactional: true,
      transactional_id: transactional_id
    )

    producer_1.init_transactions
    producer_1.begin_transaction
    producer_1.produce('Test 1', topic: topic, partition: 0)
    producer_1.produce('Test 2', topic: topic, partition: 1)
    producer_1.produce('Test 3', topic: topic, partition: 2)
    producer_1.deliver_messages

    producer_2 = kafka.producer(
      transactional: true,
      transactional_id: transactional_id
    )
    expect do
      producer_2.init_transactions
    end.to raise_error(Kafka::ConcurrentTransactionError)

    producer_1.shutdown
    producer_2.shutdown
  end

  example 'with_transaction syntax' do
    producer = kafka.producer(
      transactional: true,
      transactional_id: SecureRandom.uuid
    )

    topic = create_random_topic(num_partitions: 3)

    producer.init_transactions
    producer.with_transaction do
      producer.produce('Test 1', topic: topic, partition: 0)
      producer.produce('Test 2', topic: topic, partition: 1)
      producer.deliver_messages
      producer.produce('Test 3', topic: topic, partition: 2)
      producer.deliver_messages
    end

    records = kafka.fetch_messages(topic: topic, partition: 0, offset: :earliest, max_wait_time: 1)
    expect(records.length).to eql(1)
    expect(records[0].value).to eql('Test 1')

    records = kafka.fetch_messages(topic: topic, partition: 1, offset: :earliest, max_wait_time: 1)
    expect(records.length).to eql(1)
    expect(records[0].value).to eql('Test 2')

    records = kafka.fetch_messages(topic: topic, partition: 2, offset: :earliest, max_wait_time: 1)
    expect(records.length).to eql(1)
    expect(records[0].value).to eql('Test 3')

    producer.shutdown
  end

  example 'with_transaction block raises error' do
    producer = kafka.producer(
      transactional: true,
      transactional_id: SecureRandom.uuid
    )

    topic = create_random_topic(num_partitions: 3)

    producer.init_transactions
    expect do
      producer.with_transaction do
        producer.produce('Test 1', topic: topic, partition: 0)
        producer.produce('Test 2', topic: topic, partition: 1)
        producer.produce('Test 3', topic: topic, partition: 2)
        producer.deliver_messages
        raise 'Something went wrong'
      end
    end.to raise_error(/something went wrong/i)

    records = kafka.fetch_messages(topic: topic, partition: 0, offset: :earliest, max_wait_time: 1)
    expect(records.length).to eql(0)

    records = kafka.fetch_messages(topic: topic, partition: 1, offset: :earliest, max_wait_time: 1)
    expect(records.length).to eql(0)

    records = kafka.fetch_messages(topic: topic, partition: 2, offset: :earliest, max_wait_time: 1)
    expect(records.length).to eql(0)

    producer.shutdown
  end

  example 'with_transaction block actively aborts the transaction' do
    producer = kafka.producer(
      transactional: true,
      transactional_id: SecureRandom.uuid
    )

    topic = create_random_topic(num_partitions: 3)

    producer.init_transactions
    expect do
      producer.with_transaction do
        producer.produce('Test 1', topic: topic, partition: 0)
        producer.produce('Test 2', topic: topic, partition: 1)
        producer.produce('Test 3', topic: topic, partition: 2)
        producer.deliver_messages
        raise Kafka::Producer::AbortTransaction
      end
    end.not_to raise_error

    records = kafka.fetch_messages(topic: topic, partition: 0, offset: :earliest, max_wait_time: 1)
    expect(records.length).to eql(0)

    records = kafka.fetch_messages(topic: topic, partition: 1, offset: :earliest, max_wait_time: 1)
    expect(records.length).to eql(0)

    records = kafka.fetch_messages(topic: topic, partition: 2, offset: :earliest, max_wait_time: 1)
    expect(records.length).to eql(0)

    producer.shutdown
  end
end
