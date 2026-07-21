import NetStatCore

actor NetworkSamplingWorker {
    private let sampler = NetworkSampler()

    func reset() {
        sampler.reset()
    }

    func sample(interfaceMode: InterfaceMode) -> NetworkMeasurement {
        sampler.sample(interfaceMode: interfaceMode)
    }
}
