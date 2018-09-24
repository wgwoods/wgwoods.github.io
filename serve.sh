_dir=$(dirname $(realpath $0))
cd $_dir/reveal.js;
npm start -- --root=.. "$@"
