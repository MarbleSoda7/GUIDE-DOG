// Standalone: c++ -std=c++14 -O2 -Wno-unknown-pragmas pl_remap_accel_host_test.cpp -o test_pl_kernel
// For ap_uint C simulation: -DPL_REMAP_TEST_AP_UINT plus ap_int.h include path.
#ifndef PL_REMAP_TEST_AP_UINT
#define PL_REMAP_HOST 1
#endif
#include "pl_remap_accel.cpp"
#include <algorithm>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

static void check(bool ok, const std::string &what) {
    if (!ok) throw std::runtime_error(what);
}
static unsigned byte_at(const std::vector<word_t> &words, unsigned address) {
    return (unsigned)((words[address / 8] >> ((address % 8) * 8)) & 255u);
}
static void put_byte(std::vector<word_t> &words, unsigned address, unsigned value) {
    const unsigned shift = (address % 8) * 8;
    words[address / 8] = (words[address / 8] & ~((word_t)255u << shift)) | ((word_t)value << shift);
}
static uint32_t ref_crc(const std::vector<unsigned char> &bytes) {
    uint32_t table[256];
    for (unsigned i=0; i<256; ++i) {
        uint32_t c=i;
        for (unsigned b=0; b<8; ++b) c=(c&1) ? (c>>1)^0xedb88320u : c>>1;
        table[i]=c;
    }
    uint32_t crc=0xffffffffu;
    for (unsigned char b: bytes) crc=table[(crc^b)&255]^(crc>>8);
    return crc^0xffffffffu;
}
static uint32_t get_node(const std::vector<word_t> &lut, unsigned i) {
    return (uint32_t)(lut[i/2] >> ((i%2)*32));
}
static void set_node(std::vector<word_t> &lut, unsigned i, unsigned x, unsigned y) {
    const unsigned sh=(i%2)*32;
    const uint32_t value=x | (y<<16);
    lut[i/2]=(lut[i/2]&~((word_t)0xffffffffu<<sh))|((word_t)value<<sh);
}
static std::vector<word_t> make_lut(unsigned step, unsigned mode) {
    const unsigned cols=800/step+1, rows=480/step+1;
    std::vector<word_t> lut((cols*rows+1)/2,0);
    for (unsigned gy=0; gy<rows; ++gy) for (unsigned gx=0; gx<cols; ++gx) {
        const unsigned x=std::min(gx*step,799u), y=std::min(gy*step,479u);
        unsigned sx=x*64, sy=y*64;
        if (mode==1) { sx=std::min(x+1,799u)*64; sy=std::min(y+2,479u)*64; }
        if (mode==2) { sx=32+x*63; sy=17+y*63; }
        if (mode==3) { sx=0xffff; sy=0xffff; }
        if (mode==4 && gx==2 && gy==2) sx=0xffff;
        if (mode==5) { sx=800*64; sy=100*64; }
        if (mode==6 && gx==cols-1 && gy==rows-1) sy=0xffff;
        if (mode==7) { sx=(gx*7919+gy*1049)%(799*64+1); sy=(gx*1223+gy*6397)%(479*64+1); }
        set_node(lut,gy*cols+gx,sx,sy);
    }
    // Nonzero padding must not be treated as an extra node.
    lut.back() |= (word_t)0xdeadbeefu << 32;
    return lut;
}
static unsigned coord(const uint32_t n[4], unsigned shift, unsigned dx, unsigned dy, unsigned wx, unsigned wy) {
    uint64_t v[4];
    for (unsigned i=0; i<4; ++i) v[i]=(n[i]>>shift)&65535u;
    const uint64_t top=(v[0]*(wx-dx)+v[1]*dx)/wx;
    const uint64_t bottom=(v[2]*(wx-dx)+v[3]*dx)/wx;
    return (unsigned)((top*(wy-dy)+bottom*dy)/wy);
}
static std::vector<unsigned char> reference(const std::vector<word_t> &src, const std::vector<word_t> &lut, unsigned step, unsigned &invalid) {
    std::vector<unsigned char> out(800*480*3); invalid=0;
    const unsigned cols=800/step+1;
    for (unsigned y=0; y<480; ++y) for (unsigned x=0; x<800; ++x) {
        const unsigned gx=x/step, gy=y/step, i=gy*cols+gx;
        const unsigned wx=std::min((gx+1)*step,799u)-gx*step;
        const unsigned wy=std::min((gy+1)*step,479u)-gy*step;
        const uint32_t n[4]={get_node(lut,i),get_node(lut,i+1),get_node(lut,i+cols),get_node(lut,i+cols+1)};
        bool ok=true;
        for (unsigned k=0;k<4;++k) if ((n[k]&65535u)==65535u || (n[k]>>16)==65535u) ok=false;
        const unsigned sx=coord(n,0,x-gx*step,y-gy*step,wx,wy);
        const unsigned sy=coord(n,16,x-gx*step,y-gy*step,wx,wy);
        ok=ok && sx<=799*64 && sy<=479*64;
        if (!ok) { ++invalid; continue; }
        const unsigned xx=sx/64, yy=sy/64, nx=std::min(xx+1,799u), ny=std::min(yy+1,479u);
        const unsigned fx=sx%64, fy=sy%64;
        for (unsigned c=0;c<3;++c) {
            const unsigned a=byte_at(src,(yy*800+xx)*3+c), b=byte_at(src,(yy*800+nx)*3+c);
            const unsigned d=byte_at(src,(ny*800+xx)*3+c), e=byte_at(src,(ny*800+nx)*3+c);
            out[(y*800+x)*3+c]=(unsigned char)((a*(64-fx)*(64-fy)+b*fx*(64-fy)+d*(64-fx)*fy+e*fx*fy+2048)/4096);
        }
    }
    return out;
}
// Check constant-span division across the complete possible numerator range,
// then compare incremental signed slopes against the independent two-floor oracle.
static void check_incremental_coordinates() {
    const unsigned spans[] = {8,16,7,15};
    for (unsigned span: spans) for (unsigned n=0; n<=65535u*16u; ++n)
        if (divide_span(n,span)!=n/span) check(false,"constant span quotient");
    const uint32_t cases[][4] = {
        {0,65534,65534,0}, {65534,0,0,65534},
        {65535,65534,0,1}, {65534,65535,1,0},
        {1,2,4,7}, {7,4,2,1}, {65534,65534,65534,65534},
        {7919,49723,30311,1223}
    };
    for (unsigned wx: spans) for (unsigned wy: spans)
        for (const auto &n: cases) for (unsigned dy=0; dy<=wy; ++dy) {
            int32_t top=(int32_t)n[0]*(int32_t)wx;
            int32_t bot=(int32_t)n[2]*(int32_t)wx;
            const int32_t dt=(int32_t)n[1]-(int32_t)n[0];
            const int32_t db=(int32_t)n[3]-(int32_t)n[2];
            for (unsigned dx=0; dx<=wx; ++dx) {
                check(top>=0 && bot>=0,"sampled numerator stays nonnegative");
                check(interp_from_numerators(top,bot,dy,wx,wy)==coord(n,0,dx,dy,wx,wy),
                      "incremental two-stage floor including negative slopes and final endpoint");
                top+=dt; bot+=db;
            }
        }
    std::cout<<"PASS incremental coordinates: all four spans, signed slopes, exact two-stage floors"<<std::endl;
}
int main() {
    try {
        check_incremental_coordinates();
        const std::string known="123456789";
        std::vector<unsigned char> known_bytes(known.begin(),known.end());
        check(ref_crc(known_bytes)==0xcbf43926u,"IEEE CRC reference vector");
        unsigned kcrc=0xffffffffu;
        for (unsigned char c:known_bytes) kcrc=crc_byte(kcrc,c);
        check((kcrc^0xffffffffu)==0xcbf43926u,"kernel IEEE CRC vector");
        std::vector<word_t> src(144000,0);
        for (unsigned y=0;y<480;++y) for (unsigned x=0;x<800;++x) for(unsigned c=0;c<3;++c)
            put_byte(src,(y*800+x)*3+c,(x*37+y*59+c*83+(x*y)%251)&255);
        const std::vector<word_t> saved_src=src;
        const word_t guard=(word_t)0xfeedfacecafebeefULL;
        for (unsigned step: {8u,16u}) for (unsigned mode=0;mode<8;++mode) {
            std::vector<word_t> lut=make_lut(step,mode);
            const std::vector<word_t> saved_lut=lut;
            std::vector<word_t> out(144002,guard);
            unsigned status=99,bad=99,misses=99,pixels=99,crc=99;
            pl_remap_accel(src.data(),lut.data(),out.data()+1,step,status,bad,misses,pixels,crc);
            unsigned expected_bad=0;
            const std::vector<unsigned char> expected=reference(src,lut,step,expected_bad);
            check(status==0 && pixels==384000,"status/pixel count");
            check(bad==expected_bad,"invalid counter");
            check(crc==ref_crc(expected),"frame IEEE CRC");
            check(out.front()==guard && out.back()==guard,"output guards");
            check(src==saved_src && lut==saved_lut,"read-only source and LUT");
            for (unsigned a=0;a<expected.size();++a)
                check(byte_at(out,a+8)==expected[a],"pixel mismatch at byte "+std::to_string(a));
            if (mode==0) {
                check(bad==0 && misses==9000,"identity must read each 128B source line once");
                for(unsigned a=0;a<1152000;++a) check(byte_at(out,a+8)==byte_at(src,a),"identity including final column/row");
            }
            if (mode==3 || mode==5) check(bad==384000 && misses==0,"all invalid avoids source reads");
            if (mode==4) check(bad==4*step*step,"one invalid interior node affects four cells");
            if (mode==6) check(bad==step*step,"invalid final node includes last row and column");
            std::cout<<"PASS step="<<step<<" mode="<<mode<<" invalid="<<bad<<" cachemiss="<<misses<<" crc="<<std::hex<<crc<<std::dec<<std::endl;
        }
        for(unsigned step: {0u,1u,7u,9u,15u,17u,0xffffffffu}) {
            std::vector<word_t> out(8,guard);
            unsigned s=99,b=99,m=99,p=99,c=99;
            pl_remap_accel(nullptr,nullptr,out.data(),step,s,b,m,p,c);
            check(s==1 && b==0 && m==0 && p==0 && c==0,"bad step diagnostics");
            check(std::all_of(out.begin(),out.end(),[guard](word_t w){return w==guard;}),"bad step must not touch output");
        }
        std::cout<<"PASS: 16 full-frame references, CRC, edges, guards, cache reset, 7 bad steps"<<std::endl;
    } catch(const std::exception &e) { std::cerr<<"FAIL: "<<e.what()<<std::endl; return 1; }
    return 0;
}
