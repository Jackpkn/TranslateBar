import Cocoa
import Vision

final class VisionTextScanner {
    static let shared = VisionTextScanner()

    private init() {}

    /// Captures a screenshot of the frontmost window/screen area around mouse cursor and performs Vision OCR
    func scanTextAtCursor(completion: @escaping (String?, CGRect?) -> Void) {
        let mouseLocation = NSEvent.mouseLocation

        // Get main screen dimensions
        guard let mainScreen = NSScreen.main else {
            completion(nil, nil)
            return
        }

        let screenFrame = mainScreen.frame
        let cropWidth: CGFloat = 600
        let cropHeight: CGFloat = 300

        // Center crop rect around mouse cursor (flipped Y for CGImage coordinates)
        let cgMouseY = screenFrame.height - mouseLocation.y
        let cropX = max(0, min(mouseLocation.x - cropWidth / 2, screenFrame.width - cropWidth))
        let cropY = max(0, min(cgMouseY - cropHeight / 2, screenFrame.height - cropHeight))
        let captureRect = CGRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight)

        // Capture screen area
        guard let cgImage = CGWindowListCreateImage(
            captureRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            .bestResolution
        ) else {
            completion(nil, nil)
            return
        }

        // Run Vision OCR Request
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNRecognizeTextRequest { request, error in
            guard error == nil, let observations = request.results as? [VNRecognizedTextObservation] else {
                completion(nil, nil)
                return
            }

            var closestText: String?
            var closestRect: CGRect?
            var minDistance: CGFloat = .greatestFiniteMagnitude
            for observation in observations {
                guard let candidate = observation.topCandidates(1).first else { continue }

                // Convert normalized Vision bounding box (0.0 to 1.0) to screen coordinates
                let bbox = observation.boundingBox
                let textX = cropX + (bbox.origin.x * cropWidth)
                let textY = screenFrame.height - (cropY + ((bbox.origin.y + bbox.size.height) * cropHeight))
                let textW = bbox.size.width * cropWidth
                let textH = bbox.size.height * cropHeight
                let screenTextRect = CGRect(x: textX, y: textY, width: textW, height: textH)

                // Calculate distance to mouse cursor
                let dx = mouseLocation.x - (textX + textW / 2)
                let dy = mouseLocation.y - (textY + textH / 2)
                let dist = sqrt(dx * dx + dy * dy)

                if dist < minDistance {
                    minDistance = dist
                    closestText = candidate.string
                    closestRect = screenTextRect
                }
            }

            DispatchQueue.main.async {
                completion(closestText, closestRect)
            }
        }

        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        DispatchQueue.global(qos: .userInitiated).async {
            try? requestHandler.perform([request])
        }
    }
}
