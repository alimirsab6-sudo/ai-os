import '../../../core/result.dart';
import 'application_descriptor.dart';

abstract interface class ApplicationRegistry {
  Result<void> register(ApplicationDescriptor application);
  Result<ApplicationDescriptor> findById(String applicationId);
  List<ApplicationDescriptor> listKnownApplications();
  Result<ResolvedApplication> resolve(String applicationId);
}

