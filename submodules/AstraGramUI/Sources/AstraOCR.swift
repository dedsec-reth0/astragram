import Foundation
import UIKit
import Vision

/// Text recognition on photos, on the device (Apple Vision): no AI key needed, nothing leaves the phone.
public enum AstraOCR {
    public static func recognize(imageData: Data, completion: @escaping (Result<String, Error>) -> Void) {
        guard let image = UIImage(data: imageData), let cgImage = image.cgImage else {
            completion(.failure(AstraTextError("Image could not be read")))
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let request = VNRecognizeTextRequest(completionHandler: { request, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                completion(.success(lines.joined(separator: "\n")))
            })
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["ru-RU", "uk-UA", "en-US"]
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
            do {
                try handler.perform([request])
            } catch let error {
                completion(.failure(error))
            }
        }
    }
}
