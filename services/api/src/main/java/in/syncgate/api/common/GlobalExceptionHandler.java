package in.syncgate.api.common;

import java.util.LinkedHashMap;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.web.HttpMediaTypeNotSupportedException;
import org.springframework.web.HttpRequestMethodNotSupportedException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.MissingServletRequestParameterException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;
import org.springframework.web.multipart.MaxUploadSizeExceededException;
import org.springframework.web.multipart.support.MissingServletRequestPartException;
import org.springframework.web.servlet.resource.NoResourceFoundException;

/**
 * One error shape for every failure: {@code {code, message, details}}.
 * Messages are written for people and never contain stack traces, SQL or
 * internal class names. Unexpected errors are logged with a reference id and
 * answered with a generic 500.
 */
@RestControllerAdvice
public class GlobalExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(GlobalExceptionHandler.class);

    public record ErrorBody(String code, String message, Map<String, Object> details) {}

    @ExceptionHandler(ApiException.class)
    ResponseEntity<ErrorBody> api(ApiException e) {
        return ResponseEntity.status(e.status()).body(new ErrorBody(e.code(), e.getMessage(), e.details()));
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    ResponseEntity<ErrorBody> invalid(MethodArgumentNotValidException e) {
        Map<String, Object> fields = new LinkedHashMap<>();
        e.getBindingResult().getFieldErrors().forEach(f -> fields.put(f.getField(), f.getDefaultMessage()));
        return ResponseEntity.badRequest().body(new ErrorBody("VALIDATION", "Some fields are not valid", fields));
    }

    @ExceptionHandler({
        HttpMessageNotReadableException.class,
        MissingServletRequestParameterException.class,
        MissingServletRequestPartException.class,
        MethodArgumentTypeMismatchException.class,
        IllegalArgumentException.class
    })
    ResponseEntity<ErrorBody> badRequest(Exception e) {
        return ResponseEntity.badRequest().body(new ErrorBody("VALIDATION", "The request is not valid", Map.of()));
    }

    @ExceptionHandler(DuplicateKeyException.class)
    ResponseEntity<ErrorBody> duplicate(DuplicateKeyException e) {
        return ResponseEntity.status(HttpStatus.CONFLICT)
                .body(new ErrorBody("CONFLICT", "That record already exists", Map.of()));
    }

    @ExceptionHandler(AccessDeniedException.class)
    ResponseEntity<ErrorBody> denied(AccessDeniedException e) {
        return ResponseEntity.status(HttpStatus.FORBIDDEN)
                .body(new ErrorBody("NOT_ALLOWED", "You are not allowed to do that", Map.of()));
    }

    @ExceptionHandler(MaxUploadSizeExceededException.class)
    ResponseEntity<ErrorBody> tooLarge(MaxUploadSizeExceededException e) {
        return ResponseEntity.status(HttpStatus.CONTENT_TOO_LARGE)
                .body(new ErrorBody("TOO_LARGE", "The file is too large", Map.of()));
    }

    @ExceptionHandler(HttpRequestMethodNotSupportedException.class)
    ResponseEntity<ErrorBody> method(HttpRequestMethodNotSupportedException e) {
        return ResponseEntity.status(HttpStatus.METHOD_NOT_ALLOWED)
                .body(new ErrorBody("METHOD_NOT_ALLOWED", "Method not allowed", Map.of()));
    }

    @ExceptionHandler(HttpMediaTypeNotSupportedException.class)
    ResponseEntity<ErrorBody> media(HttpMediaTypeNotSupportedException e) {
        return ResponseEntity.status(HttpStatus.UNSUPPORTED_MEDIA_TYPE)
                .body(new ErrorBody("UNSUPPORTED_MEDIA_TYPE", "Unsupported content type", Map.of()));
    }

    @ExceptionHandler(NoResourceFoundException.class)
    ResponseEntity<ErrorBody> noResource(NoResourceFoundException e) {
        return ResponseEntity.status(HttpStatus.NOT_FOUND).body(new ErrorBody("NOT_FOUND", "Not found", Map.of()));
    }

    @ExceptionHandler(Exception.class)
    ResponseEntity<ErrorBody> unexpected(Exception e) {
        String ref = Long.toHexString(System.nanoTime());
        log.error("Unexpected error ref={}", ref, e);
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(new ErrorBody("UNEXPECTED", "Something went wrong (ref " + ref + ")", Map.of()));
    }
}
