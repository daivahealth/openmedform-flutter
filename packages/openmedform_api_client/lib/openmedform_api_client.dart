/// Typed client for the OpenMedForm API.
///
/// Kept separate from the renderer so the renderer performs no I/O and stays
/// usable inside a host — an EMR, say — that fetches forms its own way.
///
/// Start at [OmfApiClient]. The endpoint contract and the constraints that are
/// bugs if missed are in docs/ARCHITECTURE.md section 11.
library;

export 'package:openmedform_form_core/openmedform_form_core.dart'
    show OmfFormDefinition, ValidationError;

export 'src/exceptions.dart';
export 'src/models.dart';
export 'src/omf_api_client.dart';
export 'src/submission_session.dart';
