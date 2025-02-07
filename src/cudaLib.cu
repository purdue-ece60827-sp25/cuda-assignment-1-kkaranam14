
#include "cudaLib.cuh"

inline void gpuAssert(cudaError_t code, const char *file, int line, bool abort)
{
	if (code != cudaSuccess) 
	{
		fprintf(stderr,"GPUassert: %s %s %d\n", cudaGetErrorString(code), file, line);
		if (abort) exit(code);
	}
}

__global__ 
void saxpy_gpu (float* x, float* y, float scale, int size) {
	//	Insert GPU SAXPY kernel code here
        int  i = blockDim.x*blockIdx.x + threadIdx.x;
        if (i<size){
             y[i] += x[i]*scale; }
}

void ran_val( int *arr, int n){
 for (int z =0; z<n; z++){
      arr[z] = rand()%100;}}

void itf(int *iarr, float *farr, int n){
 for (int i=0; i<n; i++){
   farr[i] = (float) iarr[i];}}

int runGpuSaxpy(int vectorSize) {

        int *x, *y;
        float *h_x, *h_y;
        float scale = 2.0f;
        float *d_x, *d_y, *z;
        cudaMalloc((void **) &d_x, vectorSize*sizeof(float));
        cudaMalloc((void **) &d_y, vectorSize*sizeof(float));
        x = (int *) malloc(vectorSize*sizeof(int));
        y = (int *) malloc(vectorSize*sizeof(int));
        ran_val(x,vectorSize);
        ran_val(y,vectorSize);
        h_x = (float *) malloc(sizeof(float)*vectorSize);
        h_y = (float *) malloc(sizeof(float)*vectorSize);
        z = (float *) malloc(sizeof(float)*vectorSize);
        itf(x,h_x,vectorSize);
        itf(y,h_y,vectorSize);
        cudaMemcpy(d_x,h_x,vectorSize*sizeof(float),cudaMemcpyHostToDevice);
        cudaMemcpy(d_y,h_y,vectorSize*sizeof(float),cudaMemcpyHostToDevice); // Considering 256 threads per block)
        int numb = (vectorSize+ 255)/256;
        saxpy_gpu <<<numb,256>>>(d_x, d_y, scale, vectorSize);
        cudaDeviceSynchronize();
        cudaMemcpy(z,d_y,vectorSize*sizeof(float),cudaMemcpyDeviceToHost);
        cudaDeviceSynchronize();
        int error = verifyVector(h_x,h_y,z,scale,vectorSize);
        printf("Number of errors is %d / %d ", error, vectorSize);
        cudaFree(d_x); cudaFree(d_y); free(h_x); free(h_y); free(z); free(x); free(y);
	return 0;
}

/* 
 Some helpful definitions

 generateThreadCount is the number of threads spawned initially. Each thread is responsible for sampleSize points. 
 *pSums is a pointer to an array that holds the number of 'hit' points for each thread. The length of this array is pSumSize.

 reduceThreadCount is the number of threads used to reduce the partial sums.
 *totals is a pointer to an array that holds reduced values.
 reduceSize is the number of partial sums that each reduceThreadCount reduces.

*/

__global__
void generatePoints (uint64_t * pSums, uint64_t pSumSize, uint64_t sampleSize) {
                   uint64_t idx = blockDim.x*blockIdx.x + threadIdx.x;
                   if (idx >= pSumSize) return ;
                   curandState rng;
                   curand_init(clock64() + idx, idx, 0, &rng);
                   uint64_t hit = 0;
                   for (int i =0; i<sampleSize; i++){
                       float x = curand_uniform(&rng);
                       float y = curand_uniform(&rng);
                       if ( x*x + y*y <= 1.0f){
                           ++hit;}
}
                   pSums [idx] = hit;

 }

__global__ 
void reduceCounts (uint64_t * pSums, uint64_t * totals, uint64_t pSumSize, uint64_t reduceSize) {
	      uint64_t idx = blockDim.x*blockIdx.x + threadIdx.x;
              if (idx < reduceSize){
              uint64_t f;
              uint64_t add = 0;
              for (f = idx; f <pSumSize; f += reduceSize){
                   add += pSums[idx]; }
              totals[idx] = add;
}
 __syncthreads();
} 

int runGpuMCPi (uint64_t generateThreadCount, uint64_t sampleSize, 
	uint64_t reduceThreadCount, uint64_t reduceSize) {

	//  Check CUDA device presence
	int numDev;
	cudaGetDeviceCount(&numDev);
	if (numDev < 1) {
		std::cout << "CUDA device missing!\n";
		return -1;
	}
        
	auto tStart = std::chrono::high_resolution_clock::now();
		
	float approxPi = estimatePi(generateThreadCount, sampleSize, 
		reduceThreadCount, reduceSize);
	
	std::cout << "Estimated Pi = " << approxPi << "\n";

	auto tEnd= std::chrono::high_resolution_clock::now();

	std::chrono::duration<double> time_span = (tEnd- tStart);
	std::cout << "It took " << time_span.count() << " seconds.";

	return 0;
}

double estimatePi(uint64_t generateThreadCount, uint64_t sampleSize, 
	uint64_t reduceThreadCount, uint64_t reduceSize) {
	
	double approxPi = 0;
        uint64_t *pSums_d, *totals_d;
        uint64_t *total_final;
        cudaMalloc(&pSums_d, generateThreadCount*sizeof(uint64_t));
        cudaMalloc(&totals_d, reduceThreadCount*sizeof(uint64_t));
        total_final = (uint64_t *)malloc(reduceThreadCount*sizeof(uint64_t));
         // Assuming 1024 as the block size;
        uint64_t b = (generateThreadCount + 1023) / 1024;
        uint64_t k = (reduceThreadCount + 1023) / 1024;
        generatePoints<<<b,1024>>>(pSums_d,generateThreadCount,sampleSize);
        cudaDeviceSynchronize();
        reduceCounts<<<k,1024>>>(pSums_d,totals_d,generateThreadCount,reduceThreadCount);
        cudaDeviceSynchronize();
        cudaMemcpy(total_final,totals_d,reduceThreadCount*sizeof(uint64_t),cudaMemcpyDeviceToHost);
        uint64_t final = 0;
        for (uint64_t z=0; z<reduceThreadCount; z++){
          final += total_final[z];}
        approxPi = 4.0*static_cast<double>(final)/(generateThreadCount*sampleSize);
        cudaFree(pSums_d); cudaFree(totals_d); free(total_final);
	return approxPi;
}
