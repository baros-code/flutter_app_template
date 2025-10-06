import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:dio_http2_adapter/dio_http2_adapter.dart';
import 'package:dio_smart_retry/dio_smart_retry.dart';
import 'package:eventsource/eventsource.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

import '../../common/errors/api/api_error.dart';
import '../../common/exceptions/invalid_response_exception.dart';
import '../../common/exceptions/network_unavailable_exception.dart';
import '../../common/models/api/api_call.dart';
import '../../common/models/api/api_cancel_token.dart';
import '../../common/models/api/api_content_type.dart';
import '../../common/models/api/api_method.dart';
import '../../common/models/api/api_response_type.dart';
import '../../common/models/api/api_result.dart';
import '../../common/models/api/api_setup_params.dart';
import '../../common/utils/path_generator.dart';
import '../logging/logger.dart';
import 'connectivity_manager.dart';

/// An advanced http client to manage api operations such as get, post etc.
abstract class ApiManager {
  /// Sets up ApiManager by [setupParams]. To be called in main before runApp.
  void setup(ApiSetupParams setupParams);

  /// Sets the authorization bearer token in request headers.
  /// Can be called multiple times to update the token.
  void setBearerAuthToken(String? token);

  /// Sets the id token in request headers.
  /// Can be called multiple times to update the token.
  void setIdToken(String? idToken);

  /// Makes a call to the given [api]. See the example below.
  ///
  /// Ideally, define your API as a static method.
  /// ```dart
  /// abstract class ExampleApi {
  ///   static ApiCall<ExampleModel> getExample() {
  ///     return ApiCall(
  ///       method: ApiMethod.get,
  ///       path: '/example',
  ///       responseMapper: (response) {
  ///         return ExampleModel.fromJson(response);
  ///       },
  ///     );
  ///   }
  /// }
  /// ```
  /// Then, you can call this method passing the defined API.
  /// ```dart
  /// final example = await apiManager.call(ExampleApi.getExample());
  /// if (example.isSuccessful) print(example.value.toString());
  /// ```
  ///
  /// Additionally, you can use [cancelToken] to cancel the call.
  Future<ApiResult<TOutput>> call<TOutput extends Object>(
    ApiCall<TOutput> api, {
    ApiCancelToken? cancelToken,
  });

  Stream<ApiResult<TOutput>> callStream<TOutput extends Object>(
    ApiCall<TOutput> api, {
    ApiCancelToken? cancelToken,
  });

  /// Called when an API error occurres for any call.
  Stream<ApiError> get onApiError;
}

/// ApiManager Implementation
class ApiManagerImpl implements ApiManager {
  ApiManagerImpl(this._logger, this._connectivityManager);

  final _defaultTimeout = Duration(seconds: 30);
  final _defaultUploadAndDownloadTimeout = const Duration(seconds: 90);

  final Logger _logger;
  final ConnectivityManager _connectivityManager;

  late Dio _client;
  late HttpClientAdapter _initialHttpClientAdapter;
  late StreamController<ApiError> _onApiErrorController;

  // The IP below, should be your computer IP which you use Proxyman on it.
  String proxy = Platform.isAndroid ? '192.168.1.113:9090' : 'localhost:9090';

  @override
  void setup(ApiSetupParams setupParams) {
    // Initialize dio client.
    _client = Dio(
      BaseOptions(
        baseUrl: setupParams.baseUrl,
        headers: setupParams.baseHeaders,
        queryParameters: setupParams.baseQueryParams,
        connectTimeout: setupParams.connectTimeout ?? _defaultTimeout,
        sendTimeout: setupParams.requestTimeout ?? _defaultTimeout,
        receiveTimeout: setupParams.responseTimeout ?? _defaultTimeout,
      ),
    );

    // TODO(Baran): Uncomment if you want to use Proxyman.
    /*    if (kDebugMode) {
      // TODO(Baran): onHttpClientCreate deprecated but newer one doesn't work.
      (_client.httpClientAdapter as DefaultHttpClientAdapter)
          .onHttpClientCreate = (client) {
        client.findProxy = (url) {
          return 'PROXY $proxy';
        };

        client.badCertificateCallback =
            (X509Certificate cert, String host, int port) => Platform.isAndroid;
        return null;
      };
    } */

    // Add retry interceptor with the given retry count and delays.
    if (setupParams.retryCount != null) {
      _addRetryInterceptor(setupParams.retryCount!, setupParams.retryDelays);
    }
    // Save the initial HttpClientAdapter for a backup.
    _initialHttpClientAdapter = _client.httpClientAdapter;
    // Initialize onApiError stream controller.
    _onApiErrorController = StreamController.broadcast();
  }

  @override
  void setBearerAuthToken(String? token) {
    if (token != null) {
      _client.options.headers['authorization'] = 'Bearer $token';
      _logger.info(
        'Bearer token set : ${_client.options.headers['authorization']}',
      );
    } else {
      _client.options.headers.remove('authorization');
    }
  }

  @override
  void setIdToken(String? idToken) {
    if (idToken != null) {
      _client.options.headers['csidtoken'] = idToken;
    } else {
      _client.options.headers.remove('csidtoken');
    }
  }

  @override
  Future<ApiResult<TOutput>> call<TOutput extends Object>(
    ApiCall<TOutput> api, {
    ApiCancelToken? cancelToken,
  }) async {
    // Save old base url to revert at the end.
    final oldBaseUrl = _client.options.baseUrl;
    // Generate a uuid for logging purpose.
    final uuid = const Uuid().v4().toUpperCase();

    try {
      // Update dio client's properties as per needs.
      _updateClientByApiCallParams(api);
      // Log the api request.
      _logRequest(uuid, api, api.canLogContent);
      // Check network connectivity.
      await _checkInternetConnection();
      // Call the given api.
      final response = await _callApi(api, cancelToken);
      // Log the api response.
      _logResponse(uuid, response, api.canLogContent);
      // Return with success if response mapper is not provided
      // and the response is successful.
      if (api.responseMapper == null && _isSuccessful(response)) {
        if (api.method == ApiMethod.download) {
          final dirPath = await PathGenerator.getDownloadSaveDirectory();

          return ApiResult.success(
            value:
                PathGenerator.createDownloadedFilePath(
                      fileName: api.downloadFileName,
                      dirPath: dirPath,
                      headers: response.headers,
                      increaseFileNameCount: false,
                    )
                    as TOutput,
          );
        } else if (TOutput == String || TOutput == Uint8List) {
          return ApiResult.success(value: response.data);
        }
        return ApiResult.success();
      }
      // Validate response data by the expected response type.
      _validateResponseData(response, api.responseType);
      // Return result after mapping with the given mapper.
      if (api.responseType == ApiResponseType.json) {
        return ApiResult.success(value: api.responseMapper!(response.data));
      }
      return ApiResult.success(value: response.data);
    } on Exception catch (ex) {
      final apiError = _getApiError(ex, cancelToken, uuid);
      return ApiResult.failure(apiError);
    } finally {
      // Revert the old base url in case it's changed.
      _client.options.baseUrl = oldBaseUrl;
    }
  }

  /// Makes a streaming call to the given [api] for Server-Sent Events (SSE).
  @override
  Stream<ApiResult<TOutput>> callStream<TOutput extends Object>(
    ApiCall<TOutput> api, {
    ApiCancelToken? cancelToken,
  }) async* {
    // Generate a uuid for logging purpose.
    final uuid = const Uuid().v4().toUpperCase();
    EventSource? eventSource;
    StreamSubscription<Event>? subscription;

    try {
      // Log the api request.
      _logRequest(uuid, api, api.canLogContent);
      // Check network connectivity.
      await _checkInternetConnection();

      // Build the complete URL
      var url = api.path;

      // Add query parameters to URL if provided
      if (api.queryParams != null && api.queryParams!.isNotEmpty) {
        final uri = Uri.parse(url);
        final filteredQueryParams = <String, String>{};
        filteredQueryParams.addAll(uri.queryParameters);
        api.queryParams!.forEach((key, value) {
          if (value != null) {
            filteredQueryParams[key] = value.toString();
          }
        });
        final newUri = uri.replace(queryParameters: filteredQueryParams);
        url = newUri.toString();
      }

      // Prepare headers
      final headers = <String, String>{
        ..._client.options.headers.map(
          (key, value) => MapEntry(key, value.toString()),
        ),
        if (api.headers != null)
          ...api.headers!.map((key, value) => MapEntry(key, value.toString())),
      };

      // Create EventSource connection
      eventSource = await EventSource.connect(
        url,
        body: api.body,
        headers: headers,
      );

      _logger.debug(
        '[$uuid] SSE Connection established: $url',
        callerType: runtimeType,
      );

      // Create a stream controller to manage the events
      final streamController = StreamController<ApiResult<TOutput>>();

      // Listen to EventSource events
      subscription = eventSource.listen((event) {
        try {
          if (event.event == 'error') {
            final apiError = _getApiError(
              Exception('SSE Error event received: ${event.data}'),
              cancelToken,
              uuid,
            );
            streamController.add(ApiResult.failure(apiError));
            return;
          }

          final data = event.data;
          if (data != null && data.trim().isNotEmpty) {
            if (api.canLogContent) {
              _logger.debug(
                '[$uuid] Event: ${event.event} | Data received: $data',
                callerType: runtimeType,
              );
            }

            if (api.responseMapper != null) {
              // Try to parse as JSON if response mapper is provided
              try {
                final jsonData = jsonDecode(data);
                jsonData['event'] = event.event;
                final mappedData = api.responseMapper!(jsonData);
                streamController.add(ApiResult.success(value: mappedData));
              } catch (jsonEx) {
                // If JSON parsing fails, pass raw data
                streamController.add(ApiResult.success(value: data as TOutput));
              }
            } else {
              // Return raw data if no mapper provided
              streamController.add(ApiResult.success(value: data as TOutput));
            }
          }
        } catch (ex) {
          final apiError = _getApiError(ex as Exception, cancelToken, uuid);
          streamController.add(ApiResult.failure(apiError));
        }

        // Check if cancelled
        if (cancelToken?.token.isCancelled == true) {
          _logger.debug(
            '[$uuid] SSE Connection cancelled',
            callerType: runtimeType,
          );
          streamController.close();
        }
      });

      // Handle EventSource errors
      subscription.onError((Object error) {
        final apiError = _getApiError(
          Exception('EventSource error: $error'),
          cancelToken,
          uuid,
        );
        streamController.add(ApiResult.failure(apiError));
      });

      // Handle EventSource done
      subscription.onDone(() {
        _logger.debug('[$uuid] SSE Connection done', callerType: runtimeType);
        streamController.close();
      });

      // Yield all events from the stream controller
      await for (final result in streamController.stream) {
        yield result;
      }
    } on Exception catch (ex) {
      final apiError = _getApiError(ex, cancelToken, uuid);
      yield ApiResult.failure(apiError);
    }
  }

  @override
  Stream<ApiError> get onApiError => _onApiErrorController.stream;

  // Helpers
  void _updateClientByApiCallParams(ApiCall<dynamic> api) {
    // Ignore base url to use endpoint only if specified by the api.
    if (api.ignoreBaseUrl == true) _client.options.baseUrl = '';
    // Ignore bad certificate if specified.
    if (api.ignoreBadCertificate == true) {
      _ignoreBadCertificate();
    } else {
      // Revert ignore bad certificate.
      _client.httpClientAdapter = _initialHttpClientAdapter;
    }
  }

  Future<void> _checkInternetConnection() async {
    // Throw an exception if internet connection is not available.
    if (!(await _connectivityManager.hasConnection)) {
      throw NetworkUnavailableException();
    }
  }

  Future<Response<dynamic>> _callApi<TOutput extends Object>(
    ApiCall<TOutput> api,
    ApiCancelToken? cancelToken,
  ) {
    return api.fileDecode
        ? _decodeFile(
            api.path,
            cancelToken,
            queryParameters: api.queryParams,
            fileName: api.downloadFileName,
          )
        : api.method == ApiMethod.download
        // Download file with a given optional file name.
        ? _download(
            api.path,
            cancelToken,
            queryParameters: api.queryParams,
            fileName: api.downloadFileName,
          )
        // Call the api with the generic request method.
        : _client.request(
            api.path,
            data: api.body,
            options: Options(
              sendTimeout: api.isFileUpload
                  ? _defaultUploadAndDownloadTimeout
                  : null,
              // Parse http method from the method enum.
              method: api.method.name,
              // Combine request headers with base headers.
              headers: api.headers,
              // Set content type as per the configured content type.
              contentType: api.contentType == ApiContentType.json
                  ? 'application/json'
                  : 'charset=utf-8',
              // Set response type as per the configured response type.
              responseType: api.responseType == ApiResponseType.json
                  ? ResponseType.json
                  : api.responseType == ApiResponseType.bytes
                  ? ResponseType.bytes
                  : ResponseType.plain,
            ),
            queryParameters: api.queryParams,
            cancelToken: cancelToken?.token,
          );
  }

  Future<Response<dynamic>> _download(
    String url,
    ApiCancelToken? cancelToken, {
    Map<String, dynamic>? queryParameters,
    String? fileName,
  }) async {
    final isPermitted = await _checkPermission();
    if (!isPermitted) throw Exception('Permission not granted');

    final dirPath = await PathGenerator.getDownloadSaveDirectory();

    return _client.download(
      url,
      (Headers headers) => PathGenerator.createDownloadedFilePath(
        fileName: fileName,
        dirPath: dirPath,
        headers: headers,
      ),
      cancelToken: cancelToken?.token,
      queryParameters: queryParameters,
      options: Options(
        receiveTimeout: _defaultUploadAndDownloadTimeout,
        headers: {HttpHeaders.acceptEncodingHeader: '*'},
      ),
    );
  }

  Future<Response<dynamic>> _decodeFile(
    String url,
    ApiCancelToken? cancelToken, {
    Map<String, dynamic>? queryParameters,
    String? fileName,
  }) async {
    final isPermitted = await _checkPermission();
    if (!isPermitted) throw Exception('Permission not granted');

    final dirPath = await PathGenerator.getDownloadSaveDirectory();
    final filePath = PathGenerator.createDownloadedFilePath(
      headers: Headers(),
      fileName: fileName,
      dirPath: dirPath,
    );

    final response = await _client.request<dynamic>(
      url,
      options: Options(
        method: 'GET',
        contentType: 'application/json',
        responseType: ResponseType.json,
      ),
      queryParameters: queryParameters,
      cancelToken: cancelToken?.token,
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to download eula file');
    }
    final String base64File = response.data['file'];
    final bytes = base64Decode(base64File);
    final file = File(filePath);
    await file.writeAsBytes(bytes);
    return Response(
      data: {'id': response.data['id'], 'filePath': filePath},
      statusCode: 200,
      requestOptions: RequestOptions(path: url),
    );
  }

  void _logRequest(String uuid, ApiCall<dynamic> request, bool canLogContent) {
    final method = request.method.name.toUpperCase();
    _logger.debug(
      '[$uuid] Request: $method ${request.path}',
      callerType: runtimeType,
    );

    if (canLogContent &&
        (request.queryParams != null || request.body != null)) {
      // Log request params if provided.
      final encodedParams = jsonEncode(request.queryParams);
      if (request.queryParams != null && encodedParams.isNotEmpty) {
        _logger.debug(
          '[$uuid] RequestParams: $encodedParams',
          callerType: runtimeType,
        );
      }
      // Log request body if provided.
      final encodedBody = request.body is Map
          ? jsonEncode(request.body)
          : request.body;
      if ((encodedBody is String || encodedBody is List) &&
          encodedBody.isNotEmpty) {
        _logger.debug(
          '[$uuid] RequestBody: $encodedBody',
          callerType: runtimeType,
        );
      }
    }
  }

  void _logResponse(
    String uuid,
    Response<dynamic> response,
    bool canLogContent,
  ) {
    final isSuccessful = _isSuccessful(response);
    final responseText = '${response.statusCode} ${response.statusMessage}';
    isSuccessful
        ? _logger.debug(
            '[$uuid] Response: $responseText',
            callerType: runtimeType,
          )
        : _logger.error(
            '[$uuid] Response: $responseText',
            callerType: runtimeType,
          );

    if (canLogContent && response.data != null) {
      isSuccessful
          ? _logger.debug(
              '[$uuid] ResponseBody: ${response.toString()}',
              callerType: runtimeType,
            )
          : _logger.error(
              '[$uuid] ResponseBody: ${response.toString()}',
              callerType: runtimeType,
            );
    }
  }

  void _addRetryInterceptor(int retryCount, List<Duration>? retryDelays) {
    _client.interceptors.add(
      RetryInterceptor(
        dio: _client,
        logPrint: (message) {
          _logger.error(message, callerType: runtimeType);
        },
        retries: retryCount,
        retryDelays:
            retryDelays ??
            const [
              Duration(seconds: 1),
              Duration(seconds: 2),
              Duration(seconds: 3),
            ],
      ),
    );
  }

  void _ignoreBadCertificate() {
    _client.httpClientAdapter = Http2Adapter(
      ConnectionManager(
        // Ignore bad certificate.
        onClientCreate: (_, config) => config.onBadCertificate = (_) => true,
      ),
    );
  }

  void _validateResponseData(
    Response<dynamic> response,
    ApiResponseType responseType,
  ) {
    // Throw an exception if response is not in valid format.
    if (responseType == ApiResponseType.text && response.data is! String) {
      throw InvalidResponseException();
    }
  }

  bool _isSuccessful(Response<dynamic> response) {
    if (response.statusCode == null) return false;
    return response.statusCode! >= 200 && response.statusCode! < 300;
  }

  Future<bool> _checkPermission() async {
    if (Platform.isIOS) return true;

    if (Platform.isAndroid) {
      final info = await DeviceInfoPlugin().androidInfo;
      if (info.version.sdkInt > 28) return true;

      final status = await Permission.storage.status;
      if (status == PermissionStatus.granted) return true;

      final result = await Permission.storage.request();
      return result == PermissionStatus.granted;
    }

    throw StateError('Unknown platform');
  }

  ApiError _getApiError(
    Exception ex,
    ApiCancelToken? cancelToken,
    String uuid,
  ) {
    // Refresh cancel token to be able to use again.
    cancelToken?.refresh();
    // Log error and return in ApiResult.
    final apiError = ApiError.fromException(ex);
    _logger.error(
      '[$uuid] Error: ${apiError.toString()}',
      callerType: runtimeType,
    );
    _onApiErrorController.add(apiError);
    return apiError;
  }

  // - Helpers
}
