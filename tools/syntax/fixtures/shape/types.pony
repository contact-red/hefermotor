actor \nodoc\ Act
  fun m(): {box f[T: Any val](A, B): C} ref^ => 1
  fun n(): @{(A)} val => 1
  fun o(): ((A)) => 1
  fun p(): (A, B, (C, D)) => 1
  fun q(): A->B->C => 1
  fun r(): (A | B & C | D) => 1
  fun s(): (A & B | C) => 1
  fun t(): (A | (B | C)) => 1
  fun u(): this => 1
  fun v(): A[iso, val] => 1
  fun w[X: this->A = 3, Y]() => 1
  fun z(): U8 => "s\0t"; 1
  fun l(): {()} => 1
