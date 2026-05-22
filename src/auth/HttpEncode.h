#pragma once

#include <cctype>
#include <iomanip>
#include <sstream>
#include <string>

namespace snodec::auth {

    // RFC 3986 percent-encoding for query parameters and redirect URIs.
    //
    // The auth module carries its own encoder rather than calling the SNode.C
    // framework helper, so the Identity Provider produces correct output
    // regardless of the framework build it is compiled against. Each reserved
    // byte is emitted as "%" followed by its two-digit uppercase hex value; the
    // cast to int is what makes std::hex format the value as a number instead of
    // printing the byte as a character.
    inline std::string urlEncode(const std::string& text) {
        std::ostringstream escaped;
        escaped.fill('0');
        escaped << std::hex;

        for (const char c : text) {
            const unsigned char byte = static_cast<unsigned char>(c);
            if (std::isalnum(byte) != 0 || c == '-' || c == '_' || c == '.' || c == '~') {
                escaped << c;
            } else {
                escaped << std::uppercase;
                escaped << '%' << std::setw(2) << static_cast<int>(byte);
                escaped << std::nouppercase;
            }
        }

        return escaped.str();
    }

} // namespace snodec::auth
