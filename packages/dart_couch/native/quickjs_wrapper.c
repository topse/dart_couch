#include "quickjs_wrapper.h"
#include "quickjs.h"
#include <stdlib.h>
#include <string.h>

struct QjsEngine {
    JSRuntime *rt;
    JSContext *ctx;
};

static char *qjs_strdup(const char *s) {
    if (!s) return NULL;
    size_t len = strlen(s);
    char *dup = (char *)malloc(len + 1);
    if (dup) memcpy(dup, s, len + 1);
    return dup;
}

QjsEngine *qjs_new(void) {
    QjsEngine *engine = (QjsEngine *)malloc(sizeof(QjsEngine));
    if (!engine) return NULL;

    engine->rt = JS_NewRuntime();
    if (!engine->rt) {
        free(engine);
        return NULL;
    }

     /* Keep generous headroom for host/native call stacks during repeated evals. */
     JS_SetMaxStackSize(engine->rt, 64 * 1024 * 1024);

    engine->ctx = JS_NewContext(engine->rt);
    if (!engine->ctx) {
        JS_FreeRuntime(engine->rt);
        free(engine);
        return NULL;
    }

    return engine;
}

int qjs_eval(QjsEngine *engine, const char *code, size_t code_len,
             char **out_value, char **out_error) {
    *out_value = NULL;
    *out_error = NULL;

    /*
     * Dart async/native boundaries can shift effective C stack depth between
     * calls. Refresh stack top before every evaluation so QuickJS computes the
     * limit from the current call site instead of a stale baseline.
     */
    JS_UpdateStackTop(engine->rt);

    JSValue val = JS_Eval(engine->ctx, code, code_len, "<eval>", JS_EVAL_TYPE_GLOBAL);

    if (JS_IsException(val)) {
        JSValue exc = JS_GetException(engine->ctx);
        const char *str = JS_ToCString(engine->ctx, exc);
        *out_error = qjs_strdup(str ? str : "Unknown error");
        if (str) JS_FreeCString(engine->ctx, str);
        JS_FreeValue(engine->ctx, exc);
        return 1;
    }

    const char *str = JS_ToCString(engine->ctx, val);
    *out_value = qjs_strdup(str ? str : "");
    if (str) JS_FreeCString(engine->ctx, str);
    JS_FreeValue(engine->ctx, val);
    return 0;
}

void qjs_dispose(QjsEngine *engine) {
    if (!engine) return;
    if (engine->ctx) JS_FreeContext(engine->ctx);
    if (engine->rt) JS_FreeRuntime(engine->rt);
    free(engine);
}
