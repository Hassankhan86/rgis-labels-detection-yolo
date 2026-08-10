/// Base type for errors surfaced to the presentation layer.
sealed class Failure {
  const Failure(this.message);

  final String message;

  @override
  String toString() => message;
}

class ModelLoadFailure extends Failure {
  const ModelLoadFailure(super.message);
}

class InferenceFailure extends Failure {
  const InferenceFailure(super.message);
}

class CameraFailure extends Failure {
  const CameraFailure(super.message);
}

class StorageFailure extends Failure {
  const StorageFailure(super.message);
}

class PermissionFailure extends Failure {
  const PermissionFailure(super.message);
}