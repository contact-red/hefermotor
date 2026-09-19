actor Main
  new create(env: Env) =>
    match env.args.size()
    | if true => None
    | let n: USize if n > 1 => None
    | 0 => None
    end
