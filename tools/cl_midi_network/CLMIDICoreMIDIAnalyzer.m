#import <Foundation/Foundation.h>
#import "CLMIDICore.h"

int main(int argc,const char * argv[])
{
    @autoreleasepool
    {
        CLMIDICore *midi=[CLMIDICore new];

        [midi scanPorts];

        [midi startMonitoring];
    }

    return 0;
}
