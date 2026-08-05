#import <Foundation/Foundation.h>
#import "CLMIDICore.h"

int main(void)
{
    @autoreleasepool
    {
        CLMIDICore *midi=[CLMIDICore new];

        [midi scanPorts];

        if (![midi startMonitoring])
        {
            return 1;
        }

        [[NSRunLoop currentRunLoop] run];
    }

    return 0;
}
