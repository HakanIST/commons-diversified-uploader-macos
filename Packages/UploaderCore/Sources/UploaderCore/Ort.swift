import Foundation
import onnxruntime

/// ONNX Runtime C API'si üzerinde ince bir Swift sarmalayıcı.
public struct OrtError: Error, CustomStringConvertible {
    public let description: String
}

private let api: UnsafePointer<OrtApi> = {
    guard let base = OrtGetApiBase(), let a = base.pointee.GetApi(UInt32(ORT_API_VERSION)) else {
        fatalError("ONNX Runtime API alınamadı")
    }
    return a
}()

@inline(__always)
private func check(_ status: OpaquePointer?) throws {
    guard let status else { return }
    let message = api.pointee.GetErrorMessage(status).map { String(cString: $0) } ?? "bilinmeyen hata"
    api.pointee.ReleaseStatus(status)
    throw OrtError(description: message)
}

final class OrtEnvironment {
    static let shared = OrtEnvironment()
    let env: OpaquePointer
    let memoryInfo: OpaquePointer

    private init() {
        var e: OpaquePointer?
        try! check(api.pointee.CreateEnv(ORT_LOGGING_LEVEL_WARNING, "cdu", &e))
        env = e!
        var m: OpaquePointer?
        try! check(api.pointee.CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &m))
        memoryInfo = m!
    }
}

/// Bir OrtValue tensörü. Kendi oluşturduğumuz tensörlerde veri belleği de burada tutulur.
final class OrtTensor {
    let value: OpaquePointer
    private let storage: UnsafeMutableRawPointer?

    init(owning value: OpaquePointer) {
        self.value = value
        self.storage = nil
    }

    private init<T>(array: [T], shape: [Int], type: ONNXTensorElementDataType) throws {
        let byteCount = array.count * MemoryLayout<T>.stride
        let mem = UnsafeMutableRawPointer.allocate(byteCount: max(byteCount, 1), alignment: 16)
        array.withUnsafeBytes { if byteCount > 0 { mem.copyMemory(from: $0.baseAddress!, byteCount: byteCount) } }
        let dims = shape.map(Int64.init)
        var v: OpaquePointer?
        do {
            try check(api.pointee.CreateTensorWithDataAsOrtValue(OrtEnvironment.shared.memoryInfo, mem, byteCount, dims, dims.count, type, &v))
        } catch {
            mem.deallocate()
            throw error
        }
        value = v!
        storage = mem
    }

    // Dizinin belleği yalnızca kapanış içinde geçerlidir; kopyalama orada yapılır.
    convenience init(floats: [Float], shape: [Int]) throws {
        try self.init(array: floats, shape: shape, type: ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT)
    }

    convenience init(int64s: [Int64], shape: [Int]) throws {
        try self.init(array: int64s, shape: shape, type: ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64)
    }

    convenience init(bool: Bool) throws {
        try self.init(array: [bool], shape: [1], type: ONNX_TENSOR_ELEMENT_DATA_TYPE_BOOL)
    }

    deinit {
        api.pointee.ReleaseValue(value)
        storage?.deallocate()
    }

    var shape: [Int] {
        var info: OpaquePointer?
        guard api.pointee.GetTensorTypeAndShape(value, &info) == nil, let info else { return [] }
        defer { api.pointee.ReleaseTensorTypeAndShapeInfo(info) }
        var count = 0
        _ = api.pointee.GetDimensionsCount(info, &count)
        var dims = [Int64](repeating: 0, count: count)
        _ = api.pointee.GetDimensions(info, &dims, count)
        return dims.map(Int.init)
    }

    /// Float32 tensör verisine kopyasız erişim.
    func withFloats<R>(_ body: (UnsafeBufferPointer<Float>) throws -> R) throws -> R {
        var raw: UnsafeMutableRawPointer?
        try check(api.pointee.GetTensorMutableData(value, &raw))
        let n = shape.reduce(1, *)
        return try body(UnsafeBufferPointer(start: raw!.assumingMemoryBound(to: Float.self), count: n))
    }

    func floats() throws -> [Float] { try withFloats { Array($0) } }
}

final class OrtSession {
    private let session: OpaquePointer

    init(path: String, threads: Int = 0) throws {
        var opts: OpaquePointer?
        try check(api.pointee.CreateSessionOptions(&opts))
        defer { api.pointee.ReleaseSessionOptions(opts) }
        try check(api.pointee.SetSessionGraphOptimizationLevel(opts, ORT_ENABLE_ALL))
        if threads > 0 { try check(api.pointee.SetIntraOpNumThreads(opts, Int32(threads))) }
        var s: OpaquePointer?
        try check(api.pointee.CreateSession(OrtEnvironment.shared.env, path, opts, &s))
        session = s!
    }

    deinit { api.pointee.ReleaseSession(session) }

    func run(_ inputs: [(String, OrtTensor)], outputs: [String]) throws -> [OrtTensor] {
        let inNames = inputs.map { strdup($0.0) }
        let outNames = outputs.map { strdup($0) }
        defer { (inNames + outNames).forEach { free($0) } }
        let inValues: [OpaquePointer?] = inputs.map { $0.1.value }
        var outValues = [OpaquePointer?](repeating: nil, count: outputs.count)
        try check(api.pointee.Run(session, nil, inNames.map { UnsafePointer($0) }, inValues, inputs.count, outNames.map { UnsafePointer($0) }, outputs.count, &outValues))
        return outValues.map { OrtTensor(owning: $0!) }
    }
}
