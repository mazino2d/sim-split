import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:simsplit/core/di/injection.dart';
import 'package:simsplit/domain/entities/telemetry/error_report_settings.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';
import 'package:simsplit/presentation/utils/failure_message.dart';

part 'telemetry_providers.g.dart';

/// The error report switch, report ID and debug details (R-4 AC25–AC27).
@riverpod
Stream<ErrorReportSettings> errorReportSettings(Ref ref) =>
    ref.watch(watchErrorReportSettingsProvider)(const NoParams()).map(
          (either) => either.fold((f) => throw FailureException(f), (s) => s),
        );
