# Y

A GPU programming language that lets you speak directly to the silicon.

Most GPU languages either hide the hardware behind abstractions or expose 
it without safety. Y does neither. You get full control over shared memory 
layouts, async pipelines, and MMA atoms  with a type system that catches 
the mistakes CUDA C lets through silently.

## What makes it different

Bank conflicts are caught at compile time, not in a profiler.
The type system tracks async memory obligations — forgetting a 
barrier is a type error, not a race condition.
MMA fragment roles are enforced — passing the wrong fragment to an MMA 
op doesn't compile.

## Status

Early. The type system is being built. PTX emission comes next.

## What works right now

- SmemLayout type with swizzle parameters
- Static bank conflict verification
- Dtype system with size metadata

## License

Y says no to war. See LICENSE.

Author : Umut Korkmaz (Nadezhdo)
