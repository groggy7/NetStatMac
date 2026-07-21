import NetStatCore

actor NetworkSamplingWorker {
    private let sampler = NetworkSampler()

    func reset() {
        sampler.reset()
    }

    func sampleRate(interfaceMode: InterfaceMode) -> NetworkRate {
        sampler.sampleRate(interfaceMode: interfaceMode)
    }
}
