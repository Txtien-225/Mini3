import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

Future<String> recognizeReceipt(String path) async {
  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final result = await recognizer.processImage(InputImage.fromFilePath(path));
    return result.text;
  } finally {
    await recognizer.close();
  }
}
