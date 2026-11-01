cd [file dirname [info script]]
open_project {board_a.gprj}
set_option -top_module board_a_top
set_option -use_sspi_as_gpio 1
run all
