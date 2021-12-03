/*
 * Copyright (c) 2019 Sekhar Bhattacharya
 *
 * SPDX-License-Identifier: MIT
 */

#ifndef _PROCYON_UTILS_
#define _PROCYON_UTILS_

namespace procyon {
    namespace utils {
        typedef enum {
            DUMP_FORMAT_1B  = 1,
            DUMP_FORMAT_2B  = 2,
            DUMP_FORMAT_4B  = 4,
            DUMP_FORMAT_8B  = 8,
            DUMP_FORMAT_16B = 16,
            DUMP_FORMAT_32B = 32
        } dump_format_t;

        void load_hex(const std::string& filename, std::vector<uint8_t>& m_vec);
        void load_hex(const std::string& filename, uint8_t *m_buf, size_t size);
        void load_bin(const std::string& filename, std::vector<uint8_t>& m_vec);
        void load_bin(const std::string& filename, uint8_t *m_buf, size_t size);

        void dump_mem(const uint8_t *m_buf, size_t size, dump_format_t group_fmt, dump_format_t line_fmt);
        void dump_mem(const std::vector<uint8_t>& m_vec, dump_format_t group_fmt, dump_format_t line_fmt);
    }
}

#endif // _PROCYON_UTILS_
