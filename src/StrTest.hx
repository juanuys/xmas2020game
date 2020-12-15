class StrTest {
    static function main() {
        for (i in 0 ... 101) {
            var str = "00" + i;
            trace(str.substr(str.length - 3, 3));
        }
    }
}