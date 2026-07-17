#ifndef QUICKJS_WRAPPER_H
#define QUICKJS_WRAPPER_H

#include <stddef.h>

#if defined(_WIN32)
    #if defined(QUICKJS_WRAPPER_BUILD)
        #define QUICKJS_WRAPPER_API __declspec(dllexport)
    #else
        #define QUICKJS_WRAPPER_API __declspec(dllimport)
    #endif
#else
    #define QUICKJS_WRAPPER_API
#endif

// Opaque handle to a QuickJS runtime+context pair.
typedef struct QjsEngine QjsEngine;

// Create a new QuickJS engine (runtime + context).
QUICKJS_WRAPPER_API QjsEngine *qjs_new(void);

// Evaluate JavaScript code.
// Returns: 0 on success, non-zero on error.
// On success, *out_value is set to a malloc'd string (caller must free).
// On error, *out_error is set to a malloc'd string (caller must free).
QUICKJS_WRAPPER_API int qjs_eval(QjsEngine *engine, const char *code, size_t code_len,
                                 char **out_value, char **out_error);

// Destroy the engine and free all associated resources.
QUICKJS_WRAPPER_API void qjs_dispose(QjsEngine *engine);

#endif
