set test_script rv32ui_test.tcl
set tests [lsort [glob tests/*.hex]]

foreach test_file $tests {
    do $test_script $test_file
}

exit
