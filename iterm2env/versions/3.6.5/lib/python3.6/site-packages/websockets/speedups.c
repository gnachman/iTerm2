/* C implementation of performance sensitive functions. */

#define PY_SSIZE_T_CLEAN
#include <Python.h>
#include <stdint.h> /* uint32_t, uint64_t */

#if __SSE2__
#include <emmintrin.h>
#endif

static const Py_ssize_t MASK_LEN = 4;

static PyObject *
apply_mask(PyObject *self, PyObject *args, PyObject *kwds)
{

    // Inputs are treated as immutable, which causes an extra memory copy.

    static char *kwlist[] = {"data", "mask", NULL};
    const char *input;
    Py_ssize_t input_len;
    const char *mask;
    Py_ssize_t mask_len;

    // Initialize a PyBytesObject then get a pointer to the underlying char *
    // in order to avoid an extra memory copy in PyBytes_FromStringAndSize.

    PyObject *result;
    char *output;
    Py_ssize_t i = 0;

    if (!PyArg_ParseTupleAndKeywords(
            args, kwds, "y#y#", kwlist, &input, &input_len, &mask, &mask_len))
    {
        return NULL;
    }

    if (mask_len != MASK_LEN)
    {
        PyErr_SetString(PyExc_ValueError, "mask must contain 4 bytes");
        return NULL;
    }

    result = PyBytes_FromStringAndSize(NULL, input_len);
    if (result == NULL)
    {
        return NULL;
    }

    // Since we juste created result, we don't need error checks.
    output = PyBytes_AS_STRING(result);

    // Apparently GCC cannot figure out the following optimizations by itself.

    // We need a new scope for MSVC 2010 (non C99 friendly)
    {
#if __SSE2__

        // With SSE2 support, XOR by blocks of 16 bytes = 128 bits.

        // Since we cannot control the 16-bytes alignment of input and output
        // buffers, we rely on loadu/storeu rather than load/store.

        Py_ssize_t input_len_128 = input_len & ~15;
        __m128i mask_128 = _mm_set1_epi32(*(uint32_t *)mask);

        for (; i < input_len_128; i += 16)
        {
            __m128i in_128 = _mm_loadu_si128((__m128i *)(input + i));
            __m128i out_128 = _mm_xor_si128(in_128, mask_128);
            _mm_storeu_si128((__m128i *)(output + i), out_128);
        }

#else

        // Without SSE2 support, XOR by blocks of 8 bytes = 64 bits.

        // We assume the memory allocator aligns everything on 8 bytes boundaries.

        Py_ssize_t input_len_64 = input_len & ~7;
        uint32_t mask_32 = *(uint32_t *)mask;
        uint64_t mask_64 = ((uint64_t)mask_32 << 32) | (uint64_t)mask_32;

        for (; i < input_len_64; i += 8)
        {
            *(uint64_t *)(output + i) = *(uint64_t *)(input + i) ^ mask_64;
        }

#endif
    }

    // XOR the remainder of the input byte by byte.

    for (; i < input_len; i++)
    {
        output[i] = input[i] ^ mask[i & (MASK_LEN - 1)];
    }

    return result;

}

static PyMethodDef speedups_methods[] = {
    {
        "apply_mask",
        (PyCFunction)apply_mask,
        METH_VARARGS | METH_KEYWORDS,
        "Apply masking to websocket message.",
    },
    {NULL, NULL, 0, NULL},      /* Sentinel */
};

static struct PyModuleDef speedups_module = {
    PyModuleDef_HEAD_INIT,
    "websocket.speedups",       /* m_name */
    "C implementation of performance sensitive functions.",
                                /* m_doc */
    -1,                         /* m_size */
    speedups_methods,           /* m_methods */
    NULL,
    NULL,
    NULL,
    NULL
};

PyMODINIT_FUNC
PyInit_speedups(void)
{
    return PyModule_Create(&speedups_module);
}
